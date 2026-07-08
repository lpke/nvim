const http = require('http');
const fs = require('fs');
const path = require('path');

process.stdout.on('error', () => {});
process.stderr.on('error', () => {});

const file = path.resolve(process.argv[2]);
const root = path.resolve(process.argv[3]);
const entryRel = String(process.argv[4] || path.basename(file)).replace(/\\/g, '/');
const id = String(process.argv[5] || '');
const token = String(process.argv[6] || '');
const registryPath = String(process.argv[7] || '');
const leaseMs = Number(process.argv[8] || 300000);
const activeHeartbeatWindowMs = Number(process.argv[9] || 70000);
const reloadDebounceMs = Number(process.argv[10] || 80);
const browserKeepaliveMs = Number(process.argv[11] || 60000);

const clients = new Set();
const heartbeatClients = new Map();
let server;
let watcher;
let reloadTimer = null;
let reloadSeq = 0;
let leaseTimer = null;
let browserLeaseTimer = null;
let closed = false;
let port = null;
let watchScope = 'none';
let leaseExpiresAt = Date.now() + leaseMs;
const startedAt = Date.now();

const mime = {
  '.avif': 'image/avif',
  '.cjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.gif': 'image/gif',
  '.htm': 'text/html; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.jpeg': 'image/jpeg',
  '.jpg': 'image/jpeg',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.jsx': 'text/javascript; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml; charset=utf-8',
  '.ts': 'text/plain; charset=utf-8',
  '.tsx': 'text/plain; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.wasm': 'application/wasm',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.webp': 'image/webp',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.xml': 'application/xml; charset=utf-8',
};

const clientPath = '/__lpke_live_reload_client.js';
const eventsPath = '/__lpke_live_reload';
const triggerPath = '/__lpke_live_reload_trigger';
const statusPath = '/__lpke_live_reload_status';
const heartbeatPath = '/__lpke_live_reload_heartbeat';
const disconnectPath = '/__lpke_live_reload_disconnect';
const shutdownPath = '/__lpke_live_reload_shutdown';
const clientTag = '<script defer src="' + clientPath + '"></script>';
const clientJs = `
(() => {
  const source = new EventSource('${eventsPath}');
  source.addEventListener('reload', () => {
    window.location.reload();
  });
})();
`;

function log(payload) {
  try {
    process.stdout.write(JSON.stringify(payload) + '\n');
  } catch (_) {}
}

function clearExistingTimer(timer) {
  if (timer) clearTimeout(timer);
  return null;
}

function encodePath(relPath) {
  return '/' + relPath.split('/').filter(Boolean).map(encodeURIComponent).join('/');
}

const entryPath = encodePath(entryRel);

function isInside(target, base) {
  const rel = path.relative(base, target);
  return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
}

function shouldReloadWatchedPath(name) {
  if (!name) return true;
  const normalized = String(name).replace(/\\/g, '/');
  if (/(^|\/)(\.git|node_modules|coverage)(\/|$)/.test(normalized)) return false;
  return /\.(html?|css|mjs|cjs|jsx?|tsx?|json|svg|png|jpe?g|gif|webp|avif|ico|wasm|map|txt|xml|webmanifest|woff2?)$/i.test(normalized);
}

function ensureRegistryDir() {
  if (!registryPath) return;
  fs.mkdirSync(path.dirname(registryPath), { recursive: true });
}

function readRegistry() {
  if (!registryPath) return { version: 1, servers: {} };
  try {
    const raw = fs.readFileSync(registryPath, 'utf8');
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return { version: 1, servers: {} };
    if (!parsed.servers || typeof parsed.servers !== 'object' || Array.isArray(parsed.servers)) parsed.servers = {};
    parsed.version = 1;
    return parsed;
  } catch (_) {
    return { version: 1, servers: {} };
  }
}

function writeRegistry(data) {
  if (!registryPath) return;
  ensureRegistryDir();
  const tmp = registryPath + '.tmp.' + process.pid + '.' + Math.random().toString(16).slice(2);
  fs.writeFileSync(tmp, JSON.stringify(data), 'utf8');
  fs.renameSync(tmp, registryPath);
}

function registryEntry() {
  const urlPath = entryPath;
  return {
    id,
    path: file,
    root,
    url_path: urlPath,
    url: port ? 'http://127.0.0.1:' + port + urlPath : null,
    host: '127.0.0.1',
    port,
    pid: process.pid,
    token,
    started_at: startedAt,
    last_seen_at: Date.now(),
    lease_expires_at: leaseExpiresAt,
  };
}

function upsertRegistry() {
  try {
    const data = readRegistry();
    data.servers[file] = Object.assign({}, data.servers[file] || {}, registryEntry());
    writeRegistry(data);
  } catch (err) {
    log({ type: 'error', message: 'registry update failed: ' + (err && err.message || String(err)) });
  }
}

function removeRegistry() {
  try {
    const data = readRegistry();
    const current = data.servers[file];
    if (current && current.token === token) {
      delete data.servers[file];
      writeRegistry(data);
    }
  } catch (_) {}
}

function pruneHeartbeatClients() {
  const now = Date.now();
  for (const [instanceId, seenAt] of heartbeatClients) {
    if (now - seenAt > activeHeartbeatWindowMs) {
      heartbeatClients.delete(instanceId);
    }
  }
}

function activeHeartbeatCount() {
  pruneHeartbeatClients();
  return heartbeatClients.size;
}

function lastHeartbeatAt() {
  let latest = null;
  for (const seenAt of heartbeatClients.values()) {
    if (!latest || seenAt > latest) latest = seenAt;
  }
  return latest;
}

function statusPayload() {
  return {
    managed_by: 'lpke-ohs',
    id,
    path: file,
    root,
    url_path: entryPath,
    url: port ? 'http://127.0.0.1:' + port + entryPath : null,
    port,
    pid: process.pid,
    status: 'running',
    clients: clients.size,
    active_heartbeat_count: activeHeartbeatCount(),
    last_heartbeat_at: lastHeartbeatAt(),
    lease_expires_at: leaseExpiresAt,
    started_at: startedAt,
    watch_scope: watchScope,
  };
}

function writeJson(res, code, payload) {
  if (res.destroyed || res.writableEnded) return;
  const body = JSON.stringify(payload);
  try {
    res.writeHead(code, {
      'Cache-Control': 'no-store, max-age=0',
      'Content-Length': Buffer.byteLength(body),
      'Content-Type': 'application/json; charset=utf-8',
    });
    res.end(body);
  } catch (_) {}
}

function writeText(res, code, body) {
  if (res.destroyed || res.writableEnded) return;
  try {
    res.writeHead(code, {
      'Cache-Control': 'no-store, max-age=0',
      'Content-Length': Buffer.byteLength(body),
      'Content-Type': 'text/plain; charset=utf-8',
    });
    res.end(body);
  } catch (_) {}
}

function isAuthorized(req) {
  return token && req.headers['x-lpke-ohs-token'] === token;
}

function requireAuth(req, res) {
  if (isAuthorized(req)) return true;
  writeText(res, 403, 'Forbidden');
  return false;
}

function scheduleLeaseShutdown() {
  leaseTimer = clearExistingTimer(leaseTimer);
  const delay = Math.max(1, leaseExpiresAt - Date.now());
  leaseTimer = setTimeout(() => {
    if (Date.now() >= leaseExpiresAt) {
      shutdown('lease_expired');
      return;
    }
    scheduleLeaseShutdown();
  }, delay);
  leaseTimer.unref();
}

function renewLease(reason) {
  if (closed) return;
  leaseExpiresAt = Date.now() + leaseMs;
  scheduleLeaseShutdown();
  log({ type: 'lease', reason, lease_expires_at: leaseExpiresAt });
}

function startBrowserLeaseTimer() {
  if (browserLeaseTimer || clients.size === 0) return;
  browserLeaseTimer = setInterval(() => {
    if (clients.size > 0) {
      renewLease('browser-live-reload');
    }
  }, browserKeepaliveMs);
  browserLeaseTimer.unref();
}

function stopBrowserLeaseTimerIfIdle() {
  if (clients.size > 0 || !browserLeaseTimer) return;
  clearInterval(browserLeaseTimer);
  browserLeaseTimer = null;
}

function shutdown(reason) {
  if (closed) return;
  closed = true;
  leaseTimer = clearExistingTimer(leaseTimer);
  reloadTimer = clearExistingTimer(reloadTimer);
  if (browserLeaseTimer) {
    clearInterval(browserLeaseTimer);
    browserLeaseTimer = null;
  }

  for (const res of clients) {
    try {
      res.end();
    } catch (_) {}
  }
  clients.clear();

  if (watcher) {
    try {
      watcher.close();
    } catch (_) {}
  }

  removeRegistry();
  log({ type: 'shutdown', reason });
  if (server) {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 1000).unref();
  } else {
    process.exit(0);
  }
}

function sendReload(reason) {
  if (closed || clients.size === 0 || reloadTimer) return;
  reloadTimer = setTimeout(() => {
    reloadTimer = null;
    reloadSeq += 1;
    const payload = 'id: ' + reloadSeq + '\nevent: reload\ndata: ' + reason + '\n\n';
    for (const res of clients) {
      try {
        res.write(payload);
      } catch (_) {}
    }
    log({ type: 'reload', reason, clients: clients.size });
  }, reloadDebounceMs);
  reloadTimer.unref();
}

function injectLiveReload(html) {
  if (html.includes(clientPath)) return html;
  if (/<\/head>/i.test(html)) return html.replace(/<\/head>/i, clientTag + '</head>');
  if (/<\/body>/i.test(html)) return html.replace(/<\/body>/i, clientTag + '</body>');
  if (/<\/html>/i.test(html)) return html.replace(/<\/html>/i, clientTag + '</html>');
  return html + clientTag;
}

function writeNotFound(res) {
  writeText(res, 404, 'Not found');
}

function serveFile(req, res, target) {
  fs.readFile(target, (err, data) => {
    if (err) {
      writeNotFound(res);
      return;
    }

    const ext = path.extname(target).toLowerCase();
    const headers = {
      'Cache-Control': 'no-store, max-age=0',
      'Content-Type': mime[ext] || 'application/octet-stream',
    };

    if (/\.html?$/i.test(target)) {
      renewLease('html-request');
      data = Buffer.from(injectLiveReload(String(data)));
    }

    res.writeHead(200, headers);
    if (req.method === 'HEAD') {
      res.end();
      return;
    }
    res.end(data);
  });
}

function handleEvents(req, res) {
  renewLease('browser-live-reload');
  res.writeHead(200, {
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'Content-Type': 'text/event-stream',
  });
  res.write(': connected\n\n');

  clients.add(res);
  startBrowserLeaseTimer();
  log({ type: 'clients', count: clients.size, lease_expires_at: leaseExpiresAt });

  req.on('close', () => {
    clients.delete(res);
    log({ type: 'clients', count: clients.size, lease_expires_at: leaseExpiresAt });
    stopBrowserLeaseTimerIfIdle();
  });
}

function handleTrigger(req, res) {
  if (!requireAuth(req, res)) return;
  req.resume();
  req.on('end', () => {
    sendReload('nvim-save');
    res.writeHead(204);
    res.end();
  });
}

function handleHeartbeat(req, res) {
  if (!requireAuth(req, res)) return;
  const instanceId = String(req.headers['x-lpke-ohs-instance'] || '').trim();
  if (!instanceId) {
    writeText(res, 400, 'Missing instance id');
    return;
  }

  req.resume();
  req.on('end', () => {
    heartbeatClients.set(instanceId, Date.now());
    renewLease('nvim-heartbeat');
    writeJson(res, 200, statusPayload());
  });
}

function handleDisconnect(req, res) {
  if (!requireAuth(req, res)) return;
  const instanceId = String(req.headers['x-lpke-ohs-instance'] || '').trim();
  if (!instanceId) {
    writeText(res, 400, 'Missing instance id');
    return;
  }

  req.resume();
  req.on('end', () => {
    heartbeatClients.delete(instanceId);
    writeJson(res, 200, statusPayload());
  });
}

function handleShutdown(req, res) {
  if (!requireAuth(req, res)) return;
  req.resume();
  req.on('end', () => {
    writeJson(res, 200, { ok: true });
    setTimeout(() => shutdown('remote_stop'), 10).unref();
  });
}

function handleRequest(req, res) {
  req.on('error', () => {});
  res.on('error', () => {});

  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
  } catch (_) {
    writeText(res, 400, 'Bad request');
    return;
  }

  if (pathname === eventsPath && req.method === 'GET') {
    handleEvents(req, res);
    return;
  }

  if (pathname === clientPath && req.method === 'GET') {
    res.writeHead(200, {
      'Cache-Control': 'no-store, max-age=0',
      'Content-Length': Buffer.byteLength(clientJs),
      'Content-Type': 'text/javascript; charset=utf-8',
    });
    res.end(clientJs);
    return;
  }

  if (pathname === triggerPath && (req.method === 'POST' || req.method === 'GET')) {
    handleTrigger(req, res);
    return;
  }

  if (pathname === heartbeatPath && (req.method === 'POST' || req.method === 'GET')) {
    handleHeartbeat(req, res);
    return;
  }

  if (pathname === disconnectPath && req.method === 'POST') {
    handleDisconnect(req, res);
    return;
  }

  if (pathname === shutdownPath && req.method === 'POST') {
    handleShutdown(req, res);
    return;
  }

  if (pathname === statusPath && req.method === 'GET') {
    if (!requireAuth(req, res)) return;
    writeJson(res, 200, statusPayload());
    return;
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'Allow': 'GET, HEAD' });
    res.end();
    return;
  }

  if (pathname === '/') {
    res.writeHead(302, { 'Location': entryPath });
    res.end();
    return;
  }

  const rel = pathname.replace(/^\/+/, '');
  let target = path.resolve(root, rel);
  if (!isInside(target, root)) {
    writeText(res, 403, 'Forbidden');
    return;
  }

  fs.stat(target, (err, stat) => {
    if (err) {
      writeNotFound(res);
      return;
    }

    if (stat.isDirectory()) {
      target = path.join(target, 'index.html');
      if (!isInside(target, root)) {
        writeText(res, 403, 'Forbidden');
        return;
      }
    }

    serveFile(req, res, target);
  });
}

process.on('SIGTERM', () => shutdown('sigterm'));
process.on('SIGINT', () => shutdown('sigint'));
process.on('uncaughtException', (err) => {
  log({ type: 'error', message: err && (err.stack || err.message) || String(err) });
  removeRegistry();
  process.exit(1);
});

server = http.createServer(handleRequest);
server.on('error', (err) => {
  log({ type: 'error', message: err && err.message || String(err) });
  removeRegistry();
  process.exit(1);
});

try {
  watcher = fs.watch(root, { persistent: false, recursive: true }, (_event, name) => {
    if (shouldReloadWatchedPath(name)) sendReload('fs-watch');
  });
  watcher.unref();
  watchScope = 'root';
  log({ type: 'watch', scope: 'root' });
} catch (err) {
  try {
    watcher = fs.watch(file, { persistent: false }, () => sendReload('file-watch'));
    watcher.unref();
    watchScope = 'file';
    log({ type: 'watch', scope: 'file', message: err && err.message || '' });
  } catch (fileErr) {
    watchScope = 'none';
    log({ type: 'watch', scope: 'none', message: fileErr && fileErr.message || '' });
  }
}

scheduleLeaseShutdown();

server.listen(0, '127.0.0.1', () => {
  const address = server.address();
  port = address.port;
  upsertRegistry();
  log({
    type: 'ready',
    port,
    pid: process.pid,
    entryPath,
    file,
    root,
    lease_expires_at: leaseExpiresAt,
  });
});
