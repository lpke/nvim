local config = require('lpke.core.html_server.config')
local http = require('lpke.core.html_server.http')
local paths = require('lpke.core.html_server.paths')

local uv = vim.uv or vim.loop

local M = {}

local timer = nil
local tracked = {}
local disabled = false

local function random_suffix()
  local ok, bytes = pcall(uv.random, 6)
  if ok and bytes then
    return (
      bytes:gsub('.', function(char)
        return string.format('%02x', char:byte())
      end)
    )
  end
  return tostring(math.random(100000000, 999999999))
end

M.instance_id =
  string.format('nvim-%s-%s-%s', vim.fn.getpid(), os.time(), random_suffix())

local function tracked_count()
  local count = 0
  for _ in pairs(tracked) do
    count = count + 1
  end
  return count
end

local function stop_timer_if_idle()
  if tracked_count() > 0 then
    return
  end
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  timer = nil
end

local function send(server)
  if not server or not server.port or not server.token then
    return
  end

  http.heartbeat(server, M.instance_id, function(err, status)
    if err or type(status) ~= 'table' then
      return
    end
    server.lease_expires_at = status.lease_expires_at
    server.active_heartbeat_count = status.active_heartbeat_count
    server.last_heartbeat_at = status.last_heartbeat_at
    server.clients = status.clients
  end)
end

local function send_all()
  for _, server in pairs(tracked) do
    send(server)
  end
end

local function ensure_timer()
  if timer and not timer:is_closing() then
    return
  end
  timer = uv.new_timer()
  timer:start(
    config.heartbeat_interval_ms,
    config.heartbeat_interval_ms,
    function()
      vim.schedule(send_all)
    end
  )
end

function M.attach(server)
  if disabled then
    return
  end
  if not server or not server.path then
    return
  end
  local path = paths.normalize(server.path)
  if not path then
    return
  end
  server.path = path
  tracked[path] = server
  send(server)
  ensure_timer()
end

function M.detach(server_or_path)
  local path = type(server_or_path) == 'table' and server_or_path.path
    or server_or_path
  path = paths.normalize(path)
  if path then
    tracked[path] = nil
  end
  stop_timer_if_idle()
end

function M.is_attached(path)
  path = paths.normalize(path)
  return path and tracked[path] ~= nil or false
end

function M.disconnect_all(callback)
  disabled = true

  local servers = {}
  for _, server in pairs(tracked) do
    table.insert(servers, server)
  end
  M.stop()

  if #servers == 0 then
    if callback then
      callback(0, 0)
    end
    return
  end

  local pending = #servers
  local failed = 0
  for _, server in ipairs(servers) do
    http.disconnect(server, M.instance_id, function(err)
      if err then
        failed = failed + 1
      end
      pending = pending - 1
      if pending == 0 and callback then
        callback(#servers, failed)
      end
    end)
  end
end

function M.stop()
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  timer = nil
  tracked = {}
end

return M
