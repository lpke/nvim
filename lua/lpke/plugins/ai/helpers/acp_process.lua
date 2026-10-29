local M = {}
local uv = vim.uv
local tracked, stopping = {}, {}
local closed = setmetatable({}, { __mode = 'k' })
local births = setmetatable({}, { __mode = 'k' })
local invalid = setmetatable({}, { __mode = 'k' })
local delayed = setmetatable({}, { __mode = 'k' })
local queued = setmetatable({}, { __mode = 'k' })
local flush_scheduled, finishing = false, false
local escalations, escalation_scheduled = {}, false

local function read(path)
  local fd = uv.fs_open(path, 'r', 438)
  if not fd then
    return
  end
  local stat = uv.fs_fstat(fd)
  local data = stat and uv.fs_read(fd, stat.size > 0 and stat.size or 65536, 0)
  uv.fs_close(fd)
  return data
end

local function identity(pid)
  local stat = read('/proc/' .. pid .. '/stat')
  local fields = vim.split(
    stat and stat:match('^%d+ %b() (.*)$') or '',
    '%s+',
    { trimempty = true }
  )
  return tonumber(fields[2]), fields[20]
end

local function command(pid)
  local raw = read('/proc/' .. pid .. '/cmdline') or ''
  local args = vim.split(raw, '\0', { plain = true, trimempty = true })
  local executable = vim.fs.basename(args[1] or '')
  local interpreter = executable == 'node'
    or executable == 'nodejs'
    or executable == 'bash'
    or executable == 'sh'
    or executable == 'zsh'
    or executable:match('^python%d*%.?%d*$')
  local program = interpreter and args[2] or args[1]
  program = program or ''
  -- The installed launcher runs node .../codex-acp/dist/index.js. Examine
  -- executable/script paths, never unrelated later arguments or shell text.
  local codex = vim.fs.basename(program):match('^codex%-acp[%w_.-]*$') ~= nil
    or program:find('/codex%-acp/') ~= nil
  local native = codex and program:find('/bin/codex%-acp') ~= nil
  return raw:gsub('%z', ' '),
    codex,
    native and executable ~= 'node' and executable ~= 'nodejs'
end

local function readlink(path)
  local ok, value = pcall(uv.fs_readlink, path)
  return ok and value or nil
end

local function snapshot()
  local entries, children = {}, {}
  local dir = uv.fs_scandir('/proc')
  if not dir then
    return { entries = entries, children = children, available = false }
  end
  while true do
    local name, kind = uv.fs_scandir_next(dir)
    if not name then
      break
    end
    local pid = kind == 'directory' and tonumber(name)
    if pid then
      local parent, start = identity(pid)
      local cmdline, codex, native = command(pid)
      local entry = {
        parent = parent,
        start_time = start,
        cmdline = cmdline,
        codex = codex,
        native = native,
      }
      if codex then
        entry.cwd = readlink('/proc/' .. pid .. '/cwd')
        entry.fd_targets = {}
        for fd = 0, 2 do
          local target = readlink('/proc/' .. pid .. '/fd/' .. fd)
          -- Shared terminals or /dev/null do not establish process ownership.
          if
            target and (target:match('^pipe:%[') or target:match('^socket:%['))
          then
            entry.fd_targets[fd] = target
          end
        end
      end
      entries[pid] = entry
      if parent then
        children[parent] = children[parent] or {}
        children[parent][#children[parent] + 1] = pid
      end
    end
  end
  return { entries = entries, children = children, available = true }
end

local function overlaps(a, b)
  for _, left in pairs(a or {}) do
    for _, right in pairs(b or {}) do
      if left == right then
        return true
      end
    end
  end
  return false
end

local function remember(root, pid, entry)
  if not entry or not entry.codex or not entry.start_time then
    return
  end
  tracked[root] = tracked[root]
    or {
      owner_start_time = root == pid and entry.start_time or nil,
      children = {},
    }
  if root == pid then
    local previous = tracked[root].root
    if not previous or previous.start_time == entry.start_time then
      tracked[root].root = entry
    end
  else
    local previous = tracked[root].children[pid]
    if not previous or previous.start_time == entry.start_time then
      tracked[root].children[pid] = entry
    end
  end
end

local function refresh(root, view)
  local record = tracked[root]
  if not record then
    return
  end
  local owner = view.entries[root]
  local owner_alive = owner and owner.start_time == record.owner_start_time
  local function visit(pid)
    for _, child in ipairs(view.children[pid] or {}) do
      remember(root, child, view.entries[child])
      visit(child)
    end
  end
  if owner_alive then
    visit(root)
  end
  local related_alive = owner_alive
  for pid, previous in pairs(record.children) do
    local current = view.entries[pid]
    if
      current
      and current.codex
      and current.start_time == previous.start_time
    then
      related_alive = true
    end
  end
  local entry = record.root
  if entry and related_alive then
    for pid, candidate in pairs(view.entries) do
      if
        pid ~= root
        and candidate.codex
        and overlaps(entry.fd_targets, candidate.fd_targets)
      then
        remember(root, pid, candidate)
      end
    end
  end
end

function M.pid(conn)
  local handle = conn and conn._state and conn._state.handle
  if type(handle) ~= 'table' then
    return
  end
  local ok, pid = pcall(function()
    return handle.pid
  end)
  return ok and type(pid) == 'number' and pid or nil
end

local function track(conn, view)
  if closed[conn] or invalid[conn] then
    return
  end
  local pid = M.pid(conn)
  if pid then
    if not view.available then
      return pid
    end
    local entry = view.entries[pid]
    if not entry then
      invalid[conn] = true
      return
    end
    if not entry.start_time then
      return pid
    end
    local birth = births[conn]
    if birth and (birth.pid ~= pid or birth.start_time ~= entry.start_time) then
      invalid[conn] = true
      return
    end
    births[conn] = birth or { pid = pid, start_time = entry.start_time }
    local record = tracked[pid]
    if record and record.owner_start_time ~= entry.start_time then
      invalid[conn] = true
      return
    end
    tracked[pid] = record
      or { owner_start_time = entry.start_time, children = {} }
    remember(pid, pid, entry)
    refresh(pid, view)
  end
  return pid
end

-- Events in the same loop share one /proc snapshot; delayed passes discover
-- native children created after the Node launcher starts.
local function queue(conn)
  if not conn or closed[conn] or invalid[conn] or finishing then
    return
  end
  queued[conn] = true
  if not flush_scheduled then
    flush_scheduled = true
    vim.schedule(function()
      flush_scheduled = false
      if finishing then
        return
      end
      local connections = queued
      queued = setmetatable({}, { __mode = 'k' })
      local view = snapshot()
      for connection in pairs(connections) do
        track(connection, view)
      end
    end)
  end
end

function M.observe(conn)
  if not conn or closed[conn] or invalid[conn] or finishing then
    return
  end
  -- Bind birth identity before the next event-loop turn can reap the child.
  -- Keep it for the connection lifetime, even after tracked roots are pruned.
  if not births[conn] then
    local pid = M.pid(conn)
    if pid then
      local _, start = identity(pid)
      if start then
        births[conn] = { pid = pid, start_time = start }
      end
    end
  end
  queue(conn)
  if not delayed[conn] then
    delayed[conn] = true
    vim.defer_fn(function()
      queue(conn)
    end, 250)
    vim.defer_fn(function()
      queue(conn)
      delayed[conn] = nil
    end, 1000)
  end
end

local function matches(pid, entry)
  if not entry or not entry.start_time then
    return false
  end
  local _, start = identity(pid)
  local _, codex = command(pid)
  return start == entry.start_time and codex
end

local function signal(pid, entry, sig)
  if not matches(pid, entry) then
    return false
  end
  local ok, result = pcall(uv.kill, pid, sig)
  return ok and result ~= nil and result ~= false
end

local function signal_tree(root, sig)
  local record = tracked[root]
  if not record then
    return
  end
  for pid, entry in pairs(record.children) do
    signal(pid, entry, sig)
  end
  signal(root, record.root, sig)
end

local function prune(root)
  local record = tracked[root]
  if not record then
    return
  end
  local alive = matches(root, record.root)
  for pid, entry in pairs(record.children) do
    if matches(pid, entry) then
      alive = true
    else
      record.children[pid] = nil
    end
  end
  if not alive then
    tracked[root] = nil
  end
end

local function terminate(root, view)
  if stopping[root] or finishing then
    return
  end
  refresh(root, view)
  if not tracked[root] then
    return
  end
  stopping[root] = true
  signal_tree(root, 15)
  vim.defer_fn(function()
    if finishing then
      return
    end
    escalations[root] = true
    if not escalation_scheduled then
      escalation_scheduled = true
      vim.schedule(function()
        escalation_scheduled = false
        if finishing then
          return
        end
        local roots, view = escalations, snapshot()
        escalations = {}
        for pid in pairs(roots) do
          refresh(pid, view)
          signal_tree(pid, 9)
          prune(pid)
          stopping[pid] = nil
        end
      end)
    end
  end, 300)
end

function M.stop_tracked(keep_pid)
  local view, count = snapshot(), 0
  for root in pairs(tracked) do
    if root ~= keep_pid then
      terminate(root, view)
      count = count + 1
    end
  end
  return count
end

function M.cleanup_orphans(cwd)
  local view, count = snapshot(), 0
  for pid, entry in pairs(view.entries) do
    local parent = view.entries[entry.parent]
    if
      entry.native
      and entry.cwd == cwd
      and parent
      and parent.cmdline:find('systemd', 1, true)
      and parent.cmdline:find('%-%-user')
    then
      remember(pid, pid, entry)
      terminate(pid, view)
      count = count + 1
    end
  end
  return count
end

function M.finish()
  finishing = true
  local view = snapshot()
  for conn in pairs(queued) do
    track(conn, view)
  end
  queued = setmetatable({}, { __mode = 'k' })
  for root in pairs(tracked) do
    refresh(root, view)
  end
  for root in pairs(tracked) do
    signal_tree(root, 15)
  end
  for root in pairs(tracked) do
    signal_tree(root, 9)
  end
end

function M.patch(Connection)
  if Connection._lpke_process_cleanup then
    return
  end
  Connection._lpke_process_cleanup = true
  local start, disconnect =
    Connection.start_agent_process, Connection.disconnect
  Connection.start_agent_process = function(conn, ...)
    closed[conn], invalid[conn], births[conn] = nil, nil, nil
    local ok = start(conn, ...)
    if ok then
      M.observe(conn)
    end
    return ok
  end
  Connection.disconnect = function(conn, ...)
    if closed[conn] then
      return
    end
    local view = snapshot()
    local pid = track(conn, view)
    local owned_root = pid and tracked[pid] and matches(pid, tracked[pid].root)
    closed[conn], queued[conn] = true, nil
    if pid then
      terminate(pid, view)
    end
    if invalid[conn] then
      return
    end
    -- The pinned native disconnect only sends TERM. Owned tree teardown has
    -- already done that once; retain native teardown only as the fallback.
    if owned_root then
      return
    end
    local _, result = pcall(disconnect, conn, ...)
    return result
  end
end

return M
