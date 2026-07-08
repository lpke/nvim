local config = require('lpke.core.html_server.config')

local uv = vim.uv or vim.loop

local M = {}

local function safe_close(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

local function parse_response(raw)
  local header, body = raw:match('^(.-)\r\n\r\n(.*)$')
  header = header or raw
  body = body or ''
  local status = tonumber(header:match('^HTTP/%S+%s+(%d+)')) or 0
  local headers = {}
  for line in header:gmatch('\r\n([^\r\n]+)') do
    local key, value = line:match('^([^:]+):%s*(.*)$')
    if key then
      headers[key:lower()] = value
    end
  end
  return { status = status, headers = headers, body = body, raw = raw }
end

function M.request(opts, callback)
  opts = opts or {}
  local host = opts.host or '127.0.0.1'
  local port = tonumber(opts.port)
  if not port then
    vim.schedule(function()
      callback('missing port')
    end)
    return
  end

  local tcp = uv.new_tcp()
  if not tcp then
    vim.schedule(function()
      callback('failed to create tcp handle')
    end)
    return
  end

  local chunks = {}
  local finished = false
  local timer = uv.new_timer()

  local function finish(err, response)
    if finished then
      return
    end
    finished = true
    safe_close(timer)
    safe_close(tcp)
    vim.schedule(function()
      callback(err, response)
    end)
  end

  if timer then
    timer:start(opts.timeout_ms or config.http_timeout_ms, 0, function()
      finish('timeout')
    end)
  end

  tcp:connect(host, port, function(connect_err)
    if connect_err then
      finish(connect_err)
      return
    end

    local body = opts.body or ''
    local headers = vim.tbl_extend('force', {
      ['Connection'] = 'close',
      ['Content-Length'] = tostring(#body),
      ['Host'] = host .. ':' .. port,
    }, opts.headers or {})

    local lines = {
      (opts.method or 'GET') .. ' ' .. (opts.path or '/') .. ' HTTP/1.1',
    }
    for key, value in pairs(headers) do
      table.insert(lines, key .. ': ' .. tostring(value))
    end
    table.insert(lines, '')
    table.insert(lines, body)

    tcp:write(table.concat(lines, '\r\n'), function(write_err)
      if write_err then
        finish(write_err)
        return
      end

      tcp:read_start(function(read_err, data)
        if read_err then
          finish(read_err)
          return
        end
        if data then
          table.insert(chunks, data)
          return
        end
        finish(nil, parse_response(table.concat(chunks)))
      end)
    end)
  end)
end

local function auth_headers(entry)
  return {
    ['X-LPKE-OHS-Token'] = entry.token or '',
  }
end

local function decode_json_response(err, response, callback)
  if err then
    callback(err)
    return
  end
  if not response or response.status < 200 or response.status >= 300 then
    callback('http ' .. tostring(response and response.status or 0), response)
    return
  end

  local ok, decoded = pcall(vim.json.decode, response.body or '')
  if not ok or type(decoded) ~= 'table' then
    callback('invalid json', response)
    return
  end
  callback(nil, decoded, response)
end

function M.status(entry, callback)
  M.request({
    port = entry.port,
    path = '/__lpke_live_reload_status',
    headers = auth_headers(entry),
  }, function(err, response)
    decode_json_response(err, response, callback)
  end)
end

function M.heartbeat(entry, instance_id, callback)
  local headers = auth_headers(entry)
  headers['X-LPKE-OHS-Instance'] = instance_id
  M.request({
    method = 'POST',
    port = entry.port,
    path = '/__lpke_live_reload_heartbeat',
    headers = headers,
  }, function(err, response)
    decode_json_response(err, response, callback or function() end)
  end)
end

function M.disconnect(entry, instance_id, callback)
  local headers = auth_headers(entry)
  headers['X-LPKE-OHS-Instance'] = instance_id
  M.request({
    method = 'POST',
    port = entry.port,
    path = '/__lpke_live_reload_disconnect',
    headers = headers,
  }, function(err, response)
    decode_json_response(err, response, callback or function() end)
  end)
end

function M.shutdown(entry, callback)
  M.request({
    method = 'POST',
    port = entry.port,
    path = '/__lpke_live_reload_shutdown',
    headers = auth_headers(entry),
  }, function(err, response)
    if err then
      callback(err, response)
      return
    end
    if response and response.status >= 200 and response.status < 300 then
      callback(nil, response)
      return
    end
    callback('http ' .. tostring(response and response.status or 0), response)
  end)
end

function M.trigger_reload(entry, callback)
  M.request({
    method = 'POST',
    port = entry.port,
    path = '/__lpke_live_reload_trigger',
    headers = auth_headers(entry),
  }, callback or function() end)
end

return M
