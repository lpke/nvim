local M = {}

local Client = {}
Client.__index = Client

local CLIENT_INFO = {
  name = 'lpke_nvim',
  title = 'LPKE Neovim',
  version = '1.0.0',
}

local REMOTE_APP_SERVER = table.concat({
  'node_path=$(find "$HOME/.local/share/fnm/node-versions"',
  '-type f -path "*/installation/bin/node" -perm -111',
  '2>/dev/null | sort | tail -n 1);',
  'if [ -n "$node_path" ]; then',
  'PATH="$(dirname "$node_path"):$HOME/.local/share/npm/bin:$PATH";',
  'export PATH;',
  'fi;',
  'exec "$HOME/.local/share/npm/bin/codex" app-server',
}, ' ')

local clients = {}

local function command_for(host)
  if host == 'local' then
    return { 'codex', 'app-server' }
  end

  if host == 'mbp' then
    return {
      'ssh',
      '-T',
      '-o',
      'BatchMode=yes',
      '-o',
      'ConnectTimeout=8',
      '-o',
      'ServerAliveInterval=15',
      '-o',
      'ServerAliveCountMax=2',
      'mbp',
      REMOTE_APP_SERVER,
    }
  end

  return nil
end

local function append_bounded(lines, values, max_lines)
  for _, value in ipairs(values or {}) do
    if value ~= '' then
      table.insert(lines, value)
    end
  end

  while #lines > max_lines do
    table.remove(lines, 1)
  end
end

function Client.new(host)
  return setmetatable({
    host = host,
    job_id = nil,
    next_id = 1,
    pending = {},
    ready = false,
    ready_waiters = {},
    stderr = {},
    stdout_pending = '',
    stopping = false,
  }, Client)
end

function Client:_error_context(message)
  if #self.stderr == 0 then
    return message
  end

  local first = math.max(1, #self.stderr - 4)
  local tail = {}
  for index = first, #self.stderr do
    table.insert(tail, self.stderr[index])
  end
  return message .. '\n' .. table.concat(tail, '\n')
end

function Client:_finish_waiters(ok, err)
  local waiters = self.ready_waiters
  self.ready_waiters = {}
  for _, callback in ipairs(waiters) do
    callback(ok, err)
  end
end

function Client:_finish_pending(err)
  local pending = self.pending
  self.pending = {}
  for _, request in pairs(pending) do
    request.callback(nil, err)
  end
end

function Client:_send(message)
  if not self.job_id then
    return false
  end

  local ok, encoded = pcall(vim.json.encode, message)
  if not ok then
    return false
  end

  return vim.fn.chansend(self.job_id, encoded .. '\n') ~= 0
end

function Client:_next_request_id()
  local id = self.next_id
  self.next_id = self.next_id + 1
  return id
end

function Client:_request_now(method, params, callback, timeout_ms)
  local id = self:_next_request_id()
  self.pending[id] = {
    callback = callback,
    method = method,
  }

  if not self:_send({ method = method, id = id, params = params or {} }) then
    self.pending[id] = nil
    callback(nil, self:_error_context('Failed to write to Codex App Server'))
    return
  end

  vim.defer_fn(function()
    local request = self.pending[id]
    if not request then
      return
    end

    self.pending[id] = nil
    request.callback(
      nil,
      self:_error_context('Codex App Server timed out on ' .. request.method)
    )
  end, timeout_ms or 10000)
end

function Client:_handle_message(message)
  if message.method ~= nil or message.id == nil then
    return
  end

  local request = self.pending[message.id]
  if not request then
    return
  end

  self.pending[message.id] = nil
  if message.error then
    request.callback(nil, message.error.message or vim.inspect(message.error))
    return
  end

  request.callback(message.result, nil)
end

function Client:_handle_stdout(data)
  for index, line in ipairs(data or {}) do
    if index == 1 and self.stdout_pending ~= '' then
      line = self.stdout_pending .. line
      self.stdout_pending = ''
    end

    if index == #data and line ~= '' then
      self.stdout_pending = line
    elseif line ~= '' then
      local ok, message = pcall(vim.json.decode, line)
      if ok and type(message) == 'table' then
        self:_handle_message(message)
      end
    end
  end
end

function Client:start(callback)
  callback = callback or function() end

  if self.ready then
    callback(true, nil)
    return
  end

  table.insert(self.ready_waiters, callback)
  if self.job_id then
    return
  end

  local command = command_for(self.host)
  if not command then
    self:_finish_waiters(false, 'Unknown Codex thread host: ' .. self.host)
    return
  end

  self.stopping = false
  self.stderr = {}
  self.stdout_pending = ''

  local job_id = vim.fn.jobstart(command, {
    cwd = vim.fn.getcwd(),
    on_exit = function(_, code)
      vim.schedule(function()
        self.job_id = nil
        self.ready = false
        if self.stopping then
          self.pending = {}
          self.ready_waiters = {}
          return
        end
        local message = self:_error_context(
          'Codex App Server for ' .. self.host .. ' exited with code ' .. code
        )
        self:_finish_waiters(false, message)
        self:_finish_pending(message)
      end)
    end,
    on_stderr = function(_, data)
      vim.schedule(function()
        append_bounded(self.stderr, data, 30)
      end)
    end,
    on_stdout = function(_, data)
      vim.schedule(function()
        self:_handle_stdout(data)
      end)
    end,
    stderr_buffered = false,
    stdout_buffered = false,
  })

  if job_id <= 0 then
    self.job_id = nil
    self:_finish_waiters(
      false,
      'Failed to start Codex App Server for ' .. self.host
    )
    return
  end

  self.job_id = job_id
  self:_request_now('initialize', {
    clientInfo = CLIENT_INFO,
    capabilities = { experimentalApi = true },
  }, function(_, err)
    if err then
      self:_finish_waiters(false, err)
      self:stop()
      return
    end

    if not self:_send({ method = 'initialized', params = {} }) then
      self:_finish_waiters(false, 'Failed to initialize Codex App Server')
      self:stop()
      return
    end

    self.ready = true
    self:_finish_waiters(true, nil)
  end)
end

function Client:request(method, params, callback, timeout_ms)
  callback = callback or function() end
  if self.ready then
    self:_request_now(method, params, callback, timeout_ms)
    return
  end

  self:start(function(ok, err)
    if not ok then
      callback(nil, err)
      return
    end
    self:_request_now(method, params, callback, timeout_ms)
  end)
end

function Client:stop()
  self.stopping = true
  self.ready = false
  self.pending = {}
  self.ready_waiters = {}
  if self.job_id then
    vim.fn.jobstop(self.job_id)
  end
end

function M.get(host)
  if not clients[host] then
    clients[host] = Client.new(host)
  end
  return clients[host]
end

function M.stop_all()
  for _, client in pairs(clients) do
    client:stop()
  end
  clients = {}
end

M.Client = Client

return M
