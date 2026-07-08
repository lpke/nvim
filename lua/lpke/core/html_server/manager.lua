local config = require('lpke.core.html_server.config')
local heartbeat = require('lpke.core.html_server.heartbeat')
local http = require('lpke.core.html_server.http')
local paths = require('lpke.core.html_server.paths')
local registry = require('lpke.core.html_server.registry')

local uv = vim.uv or vim.loop

local M = {}

local servers_by_path = {}
local servers_by_port = {}
local setup_done = false
local augroup = vim.api.nvim_create_augroup('LpkeHtmlServer', { clear = true })

local function notify(message, level, opts)
  opts = opts or {}
  if opts.silent then
    return
  end
  vim.notify(message, level or vim.log.levels.INFO)
end

local function plural(count, singular, plural_word)
  return count == 1 and singular or (plural_word or singular .. 's')
end

local function now_ms()
  return os.time() * 1000
end

local function random_hex(bytes)
  local ok, data = pcall(uv.random, bytes)
  if ok and data then
    return (
      data:gsub('.', function(char)
        return string.format('%02x', char:byte())
      end)
    )
  end
  return string.format(
    '%x%x%x',
    os.time(),
    vim.fn.getpid(),
    math.random(0, 0xfffffff)
  )
end

local function is_job_running(job_id)
  return type(job_id) == 'number' and vim.fn.jobwait({ job_id }, 0)[1] == -1
end

local function cleanup_server(server)
  if not server then
    return
  end
  heartbeat.detach(server)
  if servers_by_path[server.path] == server then
    servers_by_path[server.path] = nil
  end
  if server.port and servers_by_port[server.port] == server then
    servers_by_port[server.port] = nil
  end
end

local function open_url(url, opts)
  opts = opts or {}
  if opts.no_open then
    return true
  end

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

local function entry_from_server(server)
  return {
    id = server.id,
    path = server.path,
    root = server.root,
    url_path = server.url_path,
    url = server.url,
    host = '127.0.0.1',
    port = server.port,
    pid = server.pid,
    token = server.token,
    started_at = server.started_at,
    last_seen_at = server.last_seen_at or now_ms(),
    lease_expires_at = server.lease_expires_at,
  }
end

local function status_matches(entry, status)
  if type(status) ~= 'table' then
    return false
  end
  if entry.id and status.id ~= entry.id then
    return false
  end
  if
    entry.path and paths.normalize(status.path) ~= paths.normalize(entry.path)
  then
    return false
  end
  return status.managed_by == 'lpke-ohs'
end

local function update_server_from_status(server, status)
  server.status = 'running'
  server.port = tonumber(status.port) or server.port
  server.pid = tonumber(status.pid) or server.pid
  server.clients = tonumber(status.clients) or 0
  server.active_heartbeat_count = tonumber(status.active_heartbeat_count) or 0
  server.lease_expires_at = tonumber(status.lease_expires_at)
    or server.lease_expires_at
  server.last_heartbeat_at = tonumber(status.last_heartbeat_at)
    or server.last_heartbeat_at
  server.url = status.url or server.url
  server.url_path = status.url_path or server.url_path
  if server.port then
    servers_by_port[server.port] = server
  end
end

local function adopt_entry(entry, status, opts)
  opts = opts or {}
  local path = paths.normalize(status.path or entry.path)
  if not path then
    return nil
  end

  local server = servers_by_path[path]
  if not server then
    server = {
      adopted = true,
      clients = 0,
      id = status.id or entry.id,
      job_id = nil,
      opts = {},
      path = path,
      pid = status.pid or entry.pid,
      port = status.port or entry.port,
      reloads = 0,
      root = paths.normalize(status.root or entry.root),
      started_at = status.started_at or entry.started_at,
      status = 'running',
      token = entry.token,
      url = status.url or entry.url,
      url_path = status.url_path or entry.url_path,
      watch_scope = status.watch_scope or entry.watch_scope or 'unknown',
    }
    servers_by_path[path] = server
  end

  update_server_from_status(server, status)
  if opts.heartbeat then
    heartbeat.attach(server)
  end
  return server
end

local function resolve_html_path(opts)
  opts = opts or {}
  local path = vim.api.nvim_buf_get_name(0)

  if vim.bo.buftype == '' and path ~= '' then
    path = paths.normalize(path)
    if paths.is_html(path) then
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

  if entry.type ~= 'file' or not paths.is_html(entry.name) then
    notify(
      'OHS: Selected entry is not an .html file.',
      vim.log.levels.WARN,
      opts
    )
    return nil
  end

  return paths.normalize(paths.join(dir, entry.name))
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
    server.pid = event.pid or server.pid
    server.clients = 0
    server.lease_expires_at = event.lease_expires_at
    server.url = 'http://127.0.0.1:' .. event.port .. server.url_path
    servers_by_port[event.port] = server
    local ok = registry.upsert(entry_from_server(server))
    if not ok then
      notify(
        'OHS: server started, but registry update failed.',
        vim.log.levels.WARN,
        server.opts
      )
    end
    heartbeat.attach(server)
    open_url(server.url, server.opts)
  elseif event.type == 'clients' then
    server.clients = event.count or 0
    server.lease_expires_at = event.lease_expires_at or server.lease_expires_at
  elseif event.type == 'watch' then
    server.watch_scope = event.scope
  elseif event.type == 'reload' then
    server.reloads = (server.reloads or 0) + 1
  elseif event.type == 'shutdown' then
    server.shutdown_reason = event.reason
    cleanup_server(server)
  elseif event.type == 'lease' then
    server.lease_expires_at = event.lease_expires_at
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

local function stop_local_job(server)
  if is_job_running(server.job_id) then
    vim.fn.jobstop(server.job_id)
    vim.defer_fn(function()
      if is_job_running(server.job_id) then
        vim.fn.jobstop(server.job_id)
      end
    end, 1000)
    return true
  end
  return false
end

local function stop_entry(entry, opts, callback)
  opts = opts or {}
  callback = callback or function() end

  local server = entry.path and servers_by_path[paths.normalize(entry.path)]
  if server then
    server.stopping = true
    heartbeat.detach(server)
  end

  local function finish(stopped, stale)
    if server then
      cleanup_server(server)
    end
    registry.remove(entry.path, entry.token)
    callback(stopped, stale)
  end

  if not entry.port or not entry.token then
    if server and stop_local_job(server) then
      notify('OHS: stopped ' .. server.path, vim.log.levels.INFO, opts)
      finish(true, false)
      return
    end
    notify(
      'OHS: removed stale server entry for ' .. tostring(entry.path),
      vim.log.levels.WARN,
      opts
    )
    finish(false, true)
    return
  end

  http.shutdown(entry, function(err)
    if not err then
      notify('OHS: stopped ' .. entry.path, vim.log.levels.INFO, opts)
      finish(true, false)
      return
    end

    if server and stop_local_job(server) then
      notify('OHS: stopped ' .. server.path, vim.log.levels.INFO, opts)
      finish(true, false)
      return
    end

    notify(
      'OHS: removed stale server entry for ' .. tostring(entry.path),
      vim.log.levels.WARN,
      opts
    )
    finish(false, true)
  end)
end

local function start_new(path, opts)
  opts = opts or {}

  local root = paths.root_for(path)
  local rel = paths.relative(path, root)
  local url_path = paths.url_encode_path(rel)
  local id = 'ohs-' .. os.date('!%Y%m%dT%H%M%SZ') .. '-' .. random_hex(4)
  local token = random_hex(24)

  local server = {
    clients = 0,
    id = id,
    job_id = nil,
    opts = opts,
    path = path,
    pid = nil,
    port = nil,
    reloads = 0,
    root = root,
    started_at = now_ms(),
    status = 'starting',
    stderr = {},
    stdout_pending = '',
    token = token,
    url = nil,
    url_path = url_path,
    watch_scope = 'none',
  }

  servers_by_path[path] = server

  local job_id = vim.fn.jobstart({
    'node',
    paths.node_script(),
    path,
    root,
    rel,
    id,
    token,
    registry.path,
    tostring(config.lease_ms),
    tostring(config.active_heartbeat_window_ms),
    tostring(config.reload_debounce_ms),
    tostring(config.browser_keepalive_ms),
  }, {
    cwd = root,
    detach = true,
    on_exit = function(_, code)
      vim.schedule(function()
        local stderr = table.concat(server.stderr, '\n')
        local failed = code ~= 0 and not server.stopping
        cleanup_server(server)
        registry.remove(server.path, server.token)
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
  })

  if job_id <= 0 then
    cleanup_server(server)
    notify('OHS: failed to start node server.', vim.log.levels.ERROR, opts)
    return nil
  end

  server.job_id = job_id
  server.pid = vim.fn.jobpid(job_id)

  vim.defer_fn(function()
    if servers_by_path[path] == server and server.status == 'starting' then
      server.stopping = true
      stop_local_job(server)
      cleanup_server(server)
      notify('OHS: server did not report a port.', vim.log.levels.ERROR, opts)
    end
  end, config.startup_timeout_ms)

  return server
end

local function maybe_use_registry_server(entry, opts, on_missing)
  http.status(entry, function(err, status)
    if not err and status_matches(entry, status) then
      local server = adopt_entry(entry, status, { heartbeat = true })
      if server and server.url then
        registry.upsert(entry_from_server(server))
        open_url(server.url, opts)
      end
      return
    end

    registry.remove(entry.path, entry.token)
    if on_missing then
      on_missing()
    end
  end)
end

function M.start_path(path, opts)
  opts = opts or {}
  path = paths.normalize(path)

  if not paths.is_html(path) then
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
  if
    existing
    and (existing.status == 'running' or is_job_running(existing.job_id))
  then
    if opts.restart then
      stop_entry(entry_from_server(existing), { silent = true }, function()
        start_new(path, opts)
      end)
      return existing
    end
    if existing.url then
      open_url(existing.url, opts)
    else
      notify(
        'OHS: server is still starting for ' .. path,
        vim.log.levels.INFO,
        opts
      )
    end
    heartbeat.attach(existing)
    return existing
  elseif existing then
    cleanup_server(existing)
  end

  local registry_entry = registry.find(path)
  if registry_entry then
    if opts.restart then
      stop_entry(registry_entry, { silent = true }, function()
        start_new(path, opts)
      end)
      return nil
    end
    maybe_use_registry_server(registry_entry, opts, function()
      start_new(path, opts)
    end)
    return nil
  end

  return start_new(path, opts)
end

function M.open_command(cmd)
  local path = resolve_html_path()
  if not path then
    return
  end

  local current_path = paths.normalize(vim.api.nvim_buf_get_name(0))
  if current_path == path and vim.bo.modified then
    notify(
      'OHS: Buffer has unsaved changes; browser will update after next save.',
      vim.log.levels.WARN
    )
  end

  M.start_path(path, { restart = cmd and cmd.bang })
end

local function find_memory_server(target)
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

  return servers_by_path[paths.normalize(vim.fn.expand(target))]
end

function M.stop(target, opts)
  opts = opts or {}
  local server = find_memory_server(target)
  local entry = server and entry_from_server(server) or registry.find(target)
  if not entry then
    notify('OHS: no matching server.', vim.log.levels.WARN, opts)
    return false
  end

  stop_entry(entry, opts)
  return true
end

function M.stop_all(opts)
  opts = opts or {}
  local entries_by_path = {}
  local registry_entries, registry_err = registry.entries()
  for _, entry in ipairs(registry_entries) do
    if entry.path then
      entries_by_path[paths.normalize(entry.path)] = entry
    end
  end
  for path, server in pairs(servers_by_path) do
    entries_by_path[path] = entry_from_server(server)
  end

  local entries = vim.tbl_values(entries_by_path)
  if #entries == 0 then
    if registry_err then
      notify(
        'OHS: registry file is invalid; no managed servers could be found.',
        vim.log.levels.WARN,
        opts
      )
      return
    end
    notify('OHS: no running servers.', vim.log.levels.INFO, opts)
    return
  end

  local pending = #entries
  local stopped = 0
  local stale = 0
  for _, entry in ipairs(entries) do
    stop_entry(
      vim.deepcopy(entry),
      { silent = true },
      function(did_stop, was_stale)
        pending = pending - 1
        if did_stop then
          stopped = stopped + 1
        elseif was_stale then
          stale = stale + 1
        end
        if pending == 0 then
          local parts = {}
          if stopped > 0 then
            table.insert(parts, stopped .. ' stopped')
          end
          if stale > 0 then
            table.insert(parts, stale .. ' stale removed')
          end
          notify(
            'OHS: ' .. table.concat(parts, ', ') .. '.',
            vim.log.levels.INFO,
            opts
          )
        end
      end
    )
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

function M.disconnect_current_session(opts)
  opts = opts or {}
  heartbeat.disconnect_all(function(count, failed)
    if count == 0 then
      notify(
        'OHS: this Nvim session is not keeping any servers alive.',
        vim.log.levels.INFO,
        opts
      )
      return
    end

    local message = string.format(
      'OHS: disconnected this Nvim session from %d OHS %s.',
      count,
      plural(count, 'server')
    )
    if failed and failed > 0 then
      message = message .. ' ' .. failed .. ' disconnect request failed.'
    end
    notify(
      message,
      failed and failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO,
      opts
    )
  end)
end

local function format_expiry(ms)
  if not ms then
    return 'expires:-'
  end
  return 'expires:' .. os.date('%H:%M:%S', math.floor(ms / 1000))
end

local function format_status_line(status)
  local nvim_count = tonumber(status.active_heartbeat_count) or 0
  local browser_count = tonumber(status.clients) or 0
  local current_session_marker = heartbeat.is_attached(status.path) and '*'
    or ''
  local nvim_keepalive =
    string.format('nvim-keepalive:%d%s', nvim_count, current_session_marker)
  local expiry = (nvim_count > 0 or browser_count > 0) and ''
    or ('  ' .. format_expiry(status.lease_expires_at))

  return string.format(
    '  port:%s  pid:%s  %s  %s  browser-keepalive:%d%s  %s',
    status.port or '-',
    status.pid or '-',
    status.status or 'running',
    nvim_keepalive,
    browser_count,
    expiry,
    status.path or '-'
  )
end

local function probe_entries(entries, on_done)
  if #entries == 0 then
    on_done({}, {})
    return
  end

  local rows = {}
  local stale = {}
  local pending = #entries

  for _, original in ipairs(entries) do
    local entry = vim.deepcopy(original)
    http.status(entry, function(err, status)
      pending = pending - 1
      if not err and status_matches(entry, status) then
        table.insert(rows, status)
      else
        table.insert(stale, entry)
      end
      if pending == 0 then
        table.sort(rows, function(a, b)
          return (a.path or '') < (b.path or '')
        end)
        on_done(rows, stale)
      end
    end)
  end
end

local function live_entries_from_registry_and_memory()
  local entries_by_path = {}
  local registry_entries, registry_err = registry.entries()
  for _, entry in ipairs(registry_entries) do
    if entry.path then
      entries_by_path[paths.normalize(entry.path)] = entry
    end
  end
  for path, server in pairs(servers_by_path) do
    if server.port and server.token then
      entries_by_path[path] = entry_from_server(server)
    end
  end
  return vim.tbl_values(entries_by_path), registry_err
end

function M.list()
  local entries, registry_err = live_entries_from_registry_and_memory()
  if #entries == 0 then
    if registry_err then
      notify(
        'OHS: registry file is invalid; no managed servers could be found.',
        vim.log.levels.WARN
      )
      return
    end
    notify('OHS: no running servers.')
    return
  end

  probe_entries(entries, function(rows, stale)
    registry.remove_many(stale)
    if #rows == 0 then
      local msg = 'OHS: no running servers.'
      if #stale > 0 then
        msg = msg
          .. ' Removed '
          .. #stale
          .. ' stale '
          .. plural(#stale, 'entry')
          .. '.'
      end
      notify(msg)
      return
    end

    local lines = { 'OHS servers:' }
    for _, status in ipairs(rows) do
      table.insert(lines, format_status_line(status))
    end
    if #stale > 0 then
      table.insert(lines, '  removed stale entries: ' .. #stale)
    end
    if registry_err then
      table.insert(lines, '  registry warning: invalid registry was ignored')
    end
    vim.api.nvim_echo({ { table.concat(lines, '\n') } }, true, {})
  end)
end

function M.help()
  vim.api.nvim_echo({
    {
      table.concat({
        'OHS commands:',
        '  :OHS                 Open current/Oil .html with live reload',
        '  :OHS!                Restart server for current/Oil .html',
        '  :OHSStop             Stop current file server',
        '  :OHSStop all         Stop all managed HTML live reload servers',
        '  :OHSStop <port|file> Stop specific server',
        '  :OHSDc               Stop this Nvim session from keeping servers alive',
        '  :OHSList             List live servers, keepalives, and lease expiry',
      }, '\n'),
    },
  }, true, {})
end

function M.complete_stop(arg_lead)
  local items = { 'all' }
  local seen = { all = true }

  local function add(item)
    if item and item ~= '' and not seen[item] then
      seen[item] = true
      table.insert(items, item)
    end
  end

  for _, server in pairs(servers_by_path) do
    add(server.port and tostring(server.port))
    add(server.path)
  end
  for _, entry in ipairs(registry.entries()) do
    add(entry.port and tostring(entry.port))
    add(entry.path)
  end

  return vim.tbl_filter(function(item)
    return item:sub(1, #arg_lead) == arg_lead
  end, items)
end

function M.attach_existing(opts)
  opts = opts or {}
  local entries, registry_err = registry.entries()
  if registry_err then
    notify(
      'OHS: registry file is invalid; existing servers cannot be adopted.',
      vim.log.levels.WARN,
      opts
    )
  end
  if #entries == 0 then
    return
  end

  probe_entries(entries, function(rows, stale)
    local adopted = 0
    for _, status in ipairs(rows) do
      local entry = registry.find(status.path)
      if entry and adopt_entry(entry, status, { heartbeat = true }) then
        adopted = adopted + 1
      end
    end
    registry.remove_many(stale)

    if adopted > 0 then
      local msg = string.format(
        'OHS: keeping %d HTML live reload %s alive. Use :OHSDc to disconnect this Nvim session, :OHSStop all to stop them, or :OHSHelp for help.',
        adopted,
        plural(adopted, 'server')
      )
      if #stale > 0 then
        msg = msg
          .. ' Removed '
          .. #stale
          .. ' stale '
          .. plural(#stale, 'entry')
          .. '.'
      end
      notify(msg, vim.log.levels.INFO, opts)
    elseif #stale > 0 then
      notify(
        'OHS: removed '
          .. #stale
          .. ' stale server '
          .. plural(#stale, 'entry')
          .. '.',
        vim.log.levels.INFO,
        opts
      )
    end
  end)
end

function M.setup()
  if setup_done then
    return
  end
  setup_done = true

  vim.api.nvim_create_autocmd('BufWritePost', {
    group = augroup,
    callback = function(event)
      local path = paths.normalize(vim.api.nvim_buf_get_name(event.buf))
      if not path or not paths.should_reload_on_save(path) then
        return
      end

      for _, server in pairs(servers_by_path) do
        if
          server.status == 'running'
          and server.port
          and paths.is_under(path, server.root)
        then
          http.trigger_reload(server)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd('VimEnter', {
    group = augroup,
    callback = function()
      vim.defer_fn(function()
        M.attach_existing()
      end, config.startup_scan_delay_ms)
    end,
  })

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = augroup,
    callback = function()
      heartbeat.stop()
    end,
  })

  if vim.v.vim_did_enter == 1 then
    vim.defer_fn(function()
      M.attach_existing()
    end, config.startup_scan_delay_ms)
  end
end

return M
