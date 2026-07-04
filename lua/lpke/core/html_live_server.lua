local M = {}

local uv = vim.uv or vim.loop

local servers_by_path = {}
local servers_by_port = {}
local augroup =
  vim.api.nvim_create_augroup('LpkeHtmlLiveServer', { clear = true })

local STARTUP_TIMEOUT_MS = 5000

local RELOAD_EXTENSIONS = {
  avif = true,
  cjs = true,
  css = true,
  gif = true,
  htm = true,
  html = true,
  ico = true,
  jpeg = true,
  jpg = true,
  js = true,
  json = true,
  jsx = true,
  map = true,
  mjs = true,
  png = true,
  svg = true,
  ts = true,
  tsx = true,
  txt = true,
  wasm = true,
  webmanifest = true,
  webp = true,
  woff = true,
  woff2 = true,
  xml = true,
}

local NODE_SERVER = [=[
const http = require('http');
const fs = require('fs');
const path = require('path');

const file = path.resolve(process.argv[1]);
const root = path.resolve(process.argv[2]);
const entryRel = String(process.argv[3] || path.basename(file)).replace(/\\/g, '/');
const idleMs = Number(process.env.LPKE_OHS_IDLE_MS || 15000);
const startupGraceMs = Number(process.env.LPKE_OHS_STARTUP_GRACE_MS || 30000);
const reloadDebounceMs = Number(process.env.LPKE_OHS_RELOAD_DEBOUNCE_MS || 80);

const clients = new Set();
let server;
let watcher;
let reloadTimer = null;
let reloadSeq = 0;
let idleTimer = null;
let startupTimer = null;
let closed = false;

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

function shutdown(reason) {
  if (closed) return;
  closed = true;
  idleTimer = clearExistingTimer(idleTimer);
  startupTimer = clearExistingTimer(startupTimer);
  reloadTimer = clearExistingTimer(reloadTimer);

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

  log({ type: 'shutdown', reason });
  if (server) {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 1000).unref();
  } else {
    process.exit(0);
  }
}

function scheduleIdleShutdown() {
  idleTimer = clearExistingTimer(idleTimer);
  if (clients.size === 0) {
    idleTimer = setTimeout(() => shutdown('idle'), idleMs);
    idleTimer.unref();
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
  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('Not found');
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
  res.writeHead(200, {
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'Content-Type': 'text/event-stream',
  });
  res.write(': connected\n\n');

  clients.add(res);
  startupTimer = clearExistingTimer(startupTimer);
  idleTimer = clearExistingTimer(idleTimer);
  log({ type: 'clients', count: clients.size });

  req.on('close', () => {
    clients.delete(res);
    log({ type: 'clients', count: clients.size });
    scheduleIdleShutdown();
  });
}

function handleTrigger(req, res) {
  req.resume();
  req.on('end', () => {
    sendReload('nvim-save');
    res.writeHead(204);
    res.end();
  });
}

function handleRequest(req, res) {
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
  } catch (_) {
    res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Bad request');
    return;
  }

  if (pathname === eventsPath && req.method === 'GET') {
    handleEvents(req, res);
    return;
  }

  if (pathname === clientPath && req.method === 'GET') {
    res.writeHead(200, {
      'Cache-Control': 'no-store, max-age=0',
      'Content-Type': 'text/javascript; charset=utf-8',
    });
    res.end(clientJs);
    return;
  }

  if (pathname === triggerPath && (req.method === 'POST' || req.method === 'GET')) {
    handleTrigger(req, res);
    return;
  }

  if (pathname === statusPath && req.method === 'GET') {
    res.writeHead(200, {
      'Cache-Control': 'no-store, max-age=0',
      'Content-Type': 'application/json; charset=utf-8',
    });
    res.end(JSON.stringify({ clients: clients.size, entryPath, file, root }));
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
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Forbidden');
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
        res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('Forbidden');
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
  process.exit(1);
});

server = http.createServer(handleRequest);
server.on('error', (err) => {
  log({ type: 'error', message: err && err.message || String(err) });
  process.exit(1);
});

try {
  watcher = fs.watch(root, { persistent: false, recursive: true }, (_event, name) => {
    if (shouldReloadWatchedPath(name)) sendReload('fs-watch');
  });
  watcher.unref();
  log({ type: 'watch', scope: 'root' });
} catch (err) {
  try {
    watcher = fs.watch(file, { persistent: false }, () => sendReload('file-watch'));
    watcher.unref();
    log({ type: 'watch', scope: 'file', message: err && err.message || '' });
  } catch (fileErr) {
    log({ type: 'watch', scope: 'none', message: fileErr && fileErr.message || '' });
  }
}

startupTimer = setTimeout(() => {
  if (clients.size === 0) shutdown('no_clients');
}, startupGraceMs);
startupTimer.unref();

server.listen(0, '127.0.0.1', () => {
  const address = server.address();
  log({ type: 'ready', port: address.port, entryPath, file, root });
});
]=]

local function notify(message, level, opts)
  opts = opts or {}
  if opts.silent then
    return
  end
  vim.notify(message, level or vim.log.levels.INFO)
end

local function normalize_path(path)
  if not path or path == '' then
    return nil
  end
  path = vim.fn.fnamemodify(path, ':p')
  if vim.fs and vim.fs.normalize then
    path = vim.fs.normalize(path)
  end
  if #path > 1 then
    path = path:gsub('/+$', '')
  end
  return path
end

local function join_path(dir, name)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(dir, name)
  end
  return dir:gsub('/+$', '') .. '/' .. name
end

local function is_html_path(path)
  return type(path) == 'string' and path:lower():match('%.html?$') ~= nil
end

local function path_is_under(path, root)
  if not path or not root then
    return false
  end
  if path == root then
    return true
  end
  if root == '/' then
    return path:sub(1, 1) == '/'
  end
  return path:sub(1, #root + 1) == root .. '/'
end

local function relative_path(path, root)
  if path == root then
    return ''
  end
  return path:sub(#root + 2)
end

local function url_encode(value)
  return tostring(value):gsub('[^%w%-%._~]', function(char)
    return string.format('%%%02X', char:byte())
  end)
end

local function url_encode_path(path)
  local parts = {}
  for part in path:gmatch('[^/]+') do
    table.insert(parts, (url_encode(part)))
  end
  return '/' .. table.concat(parts, '/')
end

local function is_job_running(job_id)
  return type(job_id) == 'number' and vim.fn.jobwait({ job_id }, 0)[1] == -1
end

local function cleanup_server(server)
  if servers_by_path[server.path] == server then
    servers_by_path[server.path] = nil
  end
  if server.port and servers_by_port[server.port] == server then
    servers_by_port[server.port] = nil
  end
end

local function open_url(url, opts)
  opts = opts or {}
  if vim.ui and vim.ui.open then
    local ok = pcall(vim.ui.open, url)
    if ok then
      return true
    end
  end

  if vim.fn.executable('xdg-open') == 1 then
    local jid = vim.fn.jobstart({ 'xdg-open', url }, { detach = true })
    if jid > 0 then
      return true
    end
  end

  notify('OHS: No browser command found.', vim.log.levels.ERROR, opts)
  return false
end

local function get_root(path)
  local git_root = nil
  if type(Lpke_find_git_root) == 'function' then
    git_root = Lpke_find_git_root(path)
  end
  git_root = normalize_path(git_root)
  if git_root and path_is_under(path, git_root) then
    return git_root
  end
  return normalize_path(vim.fn.fnamemodify(path, ':h'))
end

local function resolve_html_path(opts)
  opts = opts or {}
  local path = vim.api.nvim_buf_get_name(0)

  if vim.bo.buftype == '' and path ~= '' then
    path = normalize_path(path)
    if is_html_path(path) then
      return path
    end
  end

  if vim.bo.filetype ~= 'oil' then
    notify(
      'OHS: Must be used from an .html file or Oil buffer.',
      vim.log.levels.WARN,
      opts
    )
    return nil
  end

  local ok, oil = pcall(require, 'oil')
  if not ok then
    notify('OHS: oil.nvim is unavailable.', vim.log.levels.ERROR, opts)
    return nil
  end

  local dir = oil.get_current_dir()
  local entry = oil.get_cursor_entry()
  if not dir or not entry then
    notify('OHS: No Oil entry under cursor.', vim.log.levels.WARN, opts)
    return nil
  end

  if entry.type ~= 'file' or not is_html_path(entry.name) then
    notify(
      'OHS: Selected entry is not an .html file.',
      vim.log.levels.WARN,
      opts
    )
    return nil
  end

  return normalize_path(join_path(dir, entry.name))
end

local function should_reload_on_save(path)
  local ext = path:match('%.([^./]+)$')
  return ext and RELOAD_EXTENSIONS[ext:lower()] == true
end

local function safe_close(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

local function trigger_reload(server)
  if not server.port or not is_job_running(server.job_id) then
    return
  end

  local tcp = uv.new_tcp()
  if not tcp then
    return
  end

  local ok = pcall(function()
    tcp:connect('127.0.0.1', server.port, function(connect_err)
      if connect_err then
        safe_close(tcp)
        return
      end

      local request = table.concat({
        'POST /__lpke_live_reload_trigger HTTP/1.1',
        'Host: 127.0.0.1:' .. server.port,
        'Connection: close',
        'Content-Length: 0',
        '',
        '',
      }, '\r\n')

      tcp:write(request, function(write_err)
        if write_err then
          safe_close(tcp)
          return
        end

        tcp:read_start(function(_, data)
          if not data then
            safe_close(tcp)
          end
        end)
      end)
    end)
  end)

  if not ok then
    safe_close(tcp)
  end
end

local function collect_stderr(server, data)
  for _, line in ipairs(data or {}) do
    if line ~= '' then
      table.insert(server.stderr, line)
    end
  end
  while #server.stderr > 20 do
    table.remove(server.stderr, 1)
  end
end

local function handle_event(server, event)
  if servers_by_path[server.path] ~= server then
    return
  end

  if event.type == 'ready' then
    server.status = 'running'
    server.port = event.port
    server.clients = 0
    server.url = 'http://127.0.0.1:' .. event.port .. server.url_path
    servers_by_port[event.port] = server
    open_url(server.url, server.opts)
  elseif event.type == 'clients' then
    server.clients = event.count or 0
  elseif event.type == 'watch' then
    server.watch_scope = event.scope
  elseif event.type == 'reload' then
    server.reloads = (server.reloads or 0) + 1
  elseif event.type == 'shutdown' then
    server.shutdown_reason = event.reason
  elseif event.type == 'error' then
    notify(
      'OHS: ' .. (event.message or 'server error'),
      vim.log.levels.ERROR,
      server.opts
    )
  end
end

local function handle_stdout(server, data)
  for i, line in ipairs(data or {}) do
    if i == 1 and server.stdout_pending ~= '' then
      line = server.stdout_pending .. line
      server.stdout_pending = ''
    end

    if i == #data and line ~= '' then
      server.stdout_pending = line
    elseif line ~= '' then
      local ok, event = pcall(vim.json.decode, line)
      if ok and type(event) == 'table' then
        handle_event(server, event)
      end
    end
  end
end

local function stop_server(server, opts)
  opts = opts or {}
  if not server then
    return false
  end

  server.stopping = true
  cleanup_server(server)

  if is_job_running(server.job_id) then
    vim.fn.jobstop(server.job_id)
    vim.defer_fn(function()
      if is_job_running(server.job_id) then
        vim.fn.jobstop(server.job_id)
      end
    end, 1000)
  end

  notify('OHS: stopped ' .. server.path, vim.log.levels.INFO, opts)
  return true
end

local function find_server(target)
  if type(target) == 'number' then
    return servers_by_port[target]
  end

  if type(target) ~= 'string' or target == '' then
    return nil
  end

  local port = tonumber(target)
  if port then
    return servers_by_port[port]
  end

  return servers_by_path[normalize_path(vim.fn.expand(target))]
end

function M.start_path(path, opts)
  opts = opts or {}
  path = normalize_path(path)

  if not is_html_path(path) then
    notify('OHS: Target is not an .html file.', vim.log.levels.WARN, opts)
    return nil
  end

  if vim.fn.filereadable(path) ~= 1 then
    notify('OHS: File is not readable: ' .. path, vim.log.levels.ERROR, opts)
    return nil
  end

  if vim.fn.executable('node') ~= 1 then
    notify('OHS: node executable not found.', vim.log.levels.ERROR, opts)
    return nil
  end

  local existing = servers_by_path[path]
  if existing and is_job_running(existing.job_id) then
    if opts.restart then
      stop_server(existing, { silent = true })
    else
      if existing.url then
        open_url(existing.url, opts)
      else
        notify(
          'OHS: server is still starting for ' .. path,
          vim.log.levels.INFO,
          opts
        )
      end
      return existing
    end
  elseif existing then
    cleanup_server(existing)
  end

  local root = get_root(path)
  local rel = relative_path(path, root)
  local url_path = url_encode_path(rel)
  local server = {
    clients = 0,
    job_id = nil,
    pid = nil,
    opts = opts,
    path = path,
    port = nil,
    reloads = 0,
    root = root,
    status = 'starting',
    stderr = {},
    stdout_pending = '',
    url = nil,
    url_path = url_path,
    watch_scope = 'none',
  }

  servers_by_path[path] = server

  local job_id = vim.fn.jobstart(
    { 'node', '-e', NODE_SERVER, path, root, rel },
    {
      cwd = root,
      on_exit = function(_, code)
        vim.schedule(function()
          local stderr = table.concat(server.stderr, '\n')
          local failed = code ~= 0 and not server.stopping
          cleanup_server(server)
          if failed then
            local message = 'OHS: server exited with code ' .. code
            if stderr ~= '' then
              message = message .. '\n' .. stderr
            end
            notify(message, vim.log.levels.ERROR, opts)
          end
        end)
      end,
      on_stderr = function(_, data)
        vim.schedule(function()
          collect_stderr(server, data)
        end)
      end,
      on_stdout = function(_, data)
        vim.schedule(function()
          handle_stdout(server, data)
        end)
      end,
      stderr_buffered = false,
      stdout_buffered = false,
    }
  )

  if job_id <= 0 then
    cleanup_server(server)
    notify('OHS: failed to start node server.', vim.log.levels.ERROR, opts)
    return nil
  end

  server.job_id = job_id
  server.pid = vim.fn.jobpid(job_id)

  vim.defer_fn(function()
    if servers_by_path[path] == server and server.status == 'starting' then
      stop_server(server, { silent = true })
      notify('OHS: server did not report a port.', vim.log.levels.ERROR, opts)
    end
  end, STARTUP_TIMEOUT_MS)

  return server
end

function M.open_command(cmd)
  local path = resolve_html_path()
  if not path then
    return
  end

  local current_path = normalize_path(vim.api.nvim_buf_get_name(0))
  if current_path == path and vim.bo.modified then
    notify(
      'OHS: Buffer has unsaved changes; browser will update after next save.',
      vim.log.levels.WARN
    )
  end

  M.start_path(path, { restart = cmd and cmd.bang })
end

function M.stop(target, opts)
  local server = find_server(target)
  if not server then
    notify('OHS: no matching server.', vim.log.levels.WARN, opts)
    return false
  end
  return stop_server(server, opts)
end

function M.stop_all(opts)
  local servers = {}
  for _, server in pairs(servers_by_path) do
    table.insert(servers, server)
  end

  for _, server in ipairs(servers) do
    stop_server(server, opts)
  end

  if #servers == 0 then
    notify('OHS: no running servers.', vim.log.levels.INFO, opts)
  end
end

function M.stop_command(cmd)
  local target = vim.trim(cmd and cmd.args or '')
  if target == '' then
    local path = resolve_html_path({ silent = true })
    if path then
      M.stop(path)
    else
      notify('OHS: no current HTML server target.', vim.log.levels.WARN)
    end
    return
  end

  if target == 'all' then
    M.stop_all()
    return
  end

  M.stop(target)
end

function M.list()
  local rows = {}
  for _, server in pairs(servers_by_path) do
    table.insert(rows, server)
  end

  table.sort(rows, function(a, b)
    return a.path < b.path
  end)

  if #rows == 0 then
    notify('OHS: no running servers.')
    return
  end

  local lines = { 'OHS servers:' }
  for _, server in ipairs(rows) do
    table.insert(
      lines,
      string.format(
        '  port:%s  pid:%s  %s  %s client%s  %s',
        server.port or '-',
        server.pid or '-',
        server.status,
        server.clients or 0,
        server.clients == 1 and '' or 's',
        server.path
      )
    )
  end
  vim.api.nvim_echo({ { table.concat(lines, '\n') } }, true, {})
end

function M.help()
  vim.api.nvim_echo({
    {
      table.concat({
        'OHS commands:',
        '  :OHS                Open current/Oil .html with live reload',
        '  :OHS!               Restart server for current/Oil .html',
        '  :OHSStop            Stop current file server',
        '  :OHSStop all        Stop all OHS servers',
        '  :OHSStop <port|file> Stop specific server',
        '  :OHSList            List running OHS servers',
      }, '\n'),
    },
  }, true, {})
end

function M.complete_stop(arg_lead)
  local items = { 'all' }
  for _, server in pairs(servers_by_path) do
    if server.port then
      table.insert(items, tostring(server.port))
    end
    table.insert(items, server.path)
  end

  return vim.tbl_filter(function(item)
    return item:sub(1, #arg_lead) == arg_lead
  end, items)
end

vim.api.nvim_create_autocmd('BufWritePost', {
  group = augroup,
  callback = function(event)
    local path = normalize_path(vim.api.nvim_buf_get_name(event.buf))
    if not path or not should_reload_on_save(path) then
      return
    end

    for _, server in pairs(servers_by_path) do
      if
        server.status == 'running'
        and server.port
        and path_is_under(path, server.root)
      then
        trigger_reload(server)
      end
    end
  end,
})

vim.api.nvim_create_autocmd('VimLeavePre', {
  group = augroup,
  callback = function()
    M.stop_all({ silent = true })
  end,
})

return M
