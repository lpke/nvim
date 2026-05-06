local M = {}

local api = vim.api
local uv = vim.uv
local unpack = unpack or table.unpack

local augroup = api.nvim_create_augroup('LpkeCodeCompanionACPLifecycle', {
  clear = true,
})

local tracked = {}
local patched = false

local function is_acp_chat(chat)
  return chat and chat.adapter and chat.adapter.type == 'acp'
end

local function read_file(path)
  local fd = uv.fs_open(path, 'r', 438)
  if not fd then
    return nil
  end

  local stat = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return nil
  end

  local size = stat.size > 0 and stat.size or 65536
  local data = uv.fs_read(fd, size, 0)
  uv.fs_close(fd)
  return data
end

local function proc_stat(pid)
  return read_file('/proc/' .. pid .. '/stat')
end

local function proc_cmdline(pid)
  local cmdline = read_file('/proc/' .. pid .. '/cmdline')
  if not cmdline or cmdline == '' then
    return nil
  end
  return (cmdline:gsub('%z', ' '):gsub('%s+$', ''))
end

local function proc_start_time(pid)
  local stat = proc_stat(pid)
  if not stat then
    return nil
  end

  local fields = vim.split(stat:match('^%d+ %b() (.*)$') or '', '%s+', {
    trimempty = true,
  })
  return fields[20]
end

local function proc_ppid(pid)
  local stat = proc_stat(pid)
  if not stat then
    return nil
  end

  local fields = vim.split(stat:match('^%d+ %b() (.*)$') or '', '%s+', {
    trimempty = true,
  })
  return tonumber(fields[2])
end

local function proc_cwd(pid)
  local ok, cwd = pcall(uv.fs_readlink, '/proc/' .. pid .. '/cwd')
  return ok and cwd or nil
end

local function proc_fd_targets(pid)
  local targets = {}
  for _, fd in ipairs({ 0, 1, 2 }) do
    local ok, target = pcall(uv.fs_readlink, '/proc/' .. pid .. '/fd/' .. fd)
    if ok and target then
      targets[fd] = target
    end
  end
  return targets
end

local function handle_pid(handle)
  if type(handle) ~= 'table' then
    return nil
  end

  local ok, pid = pcall(function()
    return handle.pid
  end)
  if ok and type(pid) == 'number' then
    return pid
  end
  return nil
end

local function connection_handle(conn)
  return conn and conn._state and conn._state.handle
end

local function connection_pid(conn)
  return handle_pid(connection_handle(conn))
end

local function is_codex_acp_cmd(cmdline)
  return type(cmdline) == 'string' and cmdline:find('codex%-acp') ~= nil
end

local function is_native_codex_acp_cmd(cmdline)
  return is_codex_acp_cmd(cmdline)
    and cmdline:find('node%s+') == nil
    and cmdline:find('/bin/codex%-acp') ~= nil
end

local function proc_entry(pid)
  local cmdline = proc_cmdline(pid)
  if not is_codex_acp_cmd(cmdline) then
    return nil
  end

  return {
    cmdline = cmdline,
    cwd = proc_cwd(pid),
    fd_targets = proc_fd_targets(pid),
    start_time = proc_start_time(pid),
  }
end

local function list_proc_pids()
  local pids = {}
  local dir = uv.fs_scandir('/proc')
  if not dir then
    return pids
  end

  while true do
    local name, typ = uv.fs_scandir_next(dir)
    if not name then
      break
    end
    if typ == 'directory' and name:match('^%d+$') then
      table.insert(pids, tonumber(name))
    end
  end
  return pids
end

local function current_children_by_parent()
  local children = {}
  for _, pid in ipairs(list_proc_pids()) do
    local ppid = proc_ppid(pid)
    if ppid then
      children[ppid] = children[ppid] or {}
      table.insert(children[ppid], pid)
    end
  end
  return children
end

local function collect_descendants(root_pid)
  local children = current_children_by_parent()
  local descendants = {}

  local function visit(pid)
    for _, child in ipairs(children[pid] or {}) do
      table.insert(descendants, child)
      visit(child)
    end
  end

  visit(root_pid)
  return descendants
end

local function fd_targets_overlap(a, b)
  if not a or not b then
    return false
  end

  for _, left in pairs(a) do
    for _, right in pairs(b) do
      if left == right then
        return true
      end
    end
  end
  return false
end

local function related_codex_pids(root_pid, root_entry)
  local related = {}
  if not root_entry then
    return related
  end

  for _, pid in ipairs(list_proc_pids()) do
    if pid ~= root_pid then
      local entry = proc_entry(pid)
      if
        entry and fd_targets_overlap(root_entry.fd_targets, entry.fd_targets)
      then
        related[pid] = entry
      end
    end
  end

  return related
end

local function remember_pid(root_pid, pid, entry)
  if not entry then
    return
  end

  tracked[root_pid] = tracked[root_pid] or {
    children = {},
  }

  if pid == root_pid then
    tracked[root_pid].root = entry
  else
    tracked[root_pid].children[pid] = entry
  end
end

local function remember_connection(conn)
  local root_pid = connection_pid(conn)
  if not root_pid then
    return nil
  end

  local root_entry = proc_entry(root_pid)
  remember_pid(root_pid, root_pid, root_entry)
  for _, pid in ipairs(collect_descendants(root_pid)) do
    remember_pid(root_pid, pid, proc_entry(pid))
  end
  for pid, entry in pairs(related_codex_pids(root_pid, root_entry)) do
    remember_pid(root_pid, pid, entry)
  end
  return root_pid
end

local function pid_matches_record(pid, record)
  if not record then
    return false
  end

  if record.start_time and proc_start_time(pid) ~= record.start_time then
    return false
  end

  local cmdline = proc_cmdline(pid)
  return is_codex_acp_cmd(cmdline)
end

local function parent_is_user_manager(pid)
  local ppid = proc_ppid(pid)
  if not ppid then
    return false
  end

  local parent_cmd = proc_cmdline(ppid)
  return type(parent_cmd) == 'string'
    and parent_cmd:find('systemd', 1, true) ~= nil
    and parent_cmd:find('%-%-user') ~= nil
end

local function kill_recorded_pid(pid, record, signal)
  if not pid_matches_record(pid, record) then
    return false
  end

  local ok = pcall(uv.kill, pid, signal)
  return ok
end

local function kill_tracked_tree(root_pid, signal)
  local record = tracked[root_pid]
  if not record then
    return
  end

  for _, pid in ipairs(collect_descendants(root_pid)) do
    remember_pid(root_pid, pid, proc_entry(pid))
  end
  for pid, entry in pairs(related_codex_pids(root_pid, record.root)) do
    remember_pid(root_pid, pid, entry)
  end

  for pid, entry in pairs(record.children or {}) do
    kill_recorded_pid(pid, entry, signal)
  end

  kill_recorded_pid(root_pid, record.root, signal)
end

local function prune_tree(root_pid)
  local record = tracked[root_pid]
  if not record then
    return
  end

  local alive = false
  if pid_matches_record(root_pid, record.root) then
    alive = true
  end

  for pid, entry in pairs(record.children or {}) do
    if pid_matches_record(pid, entry) then
      alive = true
    else
      record.children[pid] = nil
    end
  end

  if not alive then
    tracked[root_pid] = nil
  end
end

local function saved_session_id(chat)
  return chat
    and (
      chat.acp_session_id
      or (chat.opts and chat.opts.acp_session_id)
      or (chat.acp_connection and chat.acp_connection.session_id)
    )
end

function M.remember_session(chat)
  if not is_acp_chat(chat) then
    return nil
  end

  local session_id = saved_session_id(chat)
  if not session_id then
    return nil
  end

  chat.acp_session_id = session_id
  chat.opts = chat.opts or {}
  chat.opts.acp_session_id = session_id
  return session_id
end

function M.get_session_id(chat)
  return saved_session_id(chat)
end

function M.track_chat(chat)
  if not is_acp_chat(chat) or not chat.acp_connection then
    return
  end

  M.remember_session(chat)
  local conn = chat.acp_connection
  remember_connection(conn)
  vim.defer_fn(function()
    remember_connection(conn)
  end, 1000)
end

function M.cleanup_stale_orphans()
  local cwd = vim.fn.getcwd()
  local killed = 0

  for _, pid in ipairs(list_proc_pids()) do
    local cmdline = proc_cmdline(pid)
    if
      is_native_codex_acp_cmd(cmdline)
      and proc_cwd(pid) == cwd
      and parent_is_user_manager(pid)
    then
      local entry = proc_entry(pid)
      if kill_recorded_pid(pid, entry, 15) then
        killed = killed + 1
      end
      vim.defer_fn(function()
        kill_recorded_pid(pid, entry, 9)
      end, 300)
    end
  end

  return killed
end

local function disconnect_connection(conn)
  if not conn then
    return
  end

  local root_pid = remember_connection(conn)

  if root_pid then
    kill_tracked_tree(root_pid, 15)
  end

  pcall(function()
    conn:disconnect()
  end)

  if root_pid then
    vim.defer_fn(function()
      kill_tracked_tree(root_pid, 9)
      prune_tree(root_pid)
    end, 300)
  end
end

function M.suspend_chat(chat, opts)
  opts = opts or {}
  if not is_acp_chat(chat) or not chat.acp_connection then
    return false
  end

  local conn = chat.acp_connection
  M.remember_session(chat)
  remember_connection(conn)

  if opts.stop_request and chat.current_request then
    pcall(function()
      chat:stop()
    end)
  elseif opts.cancel_prompt ~= false and conn.session_id then
    pcall(function()
      conn:send_notification(conn.METHODS.SESSION_CANCEL, {
        sessionId = conn.session_id,
      })
    end)
  end

  if chat.acp_connection == conn then
    chat.acp_connection = nil
  end

  local delay = opts.delay_ms or 0
  if delay > 0 then
    vim.defer_fn(function()
      disconnect_connection(conn)
    end, delay)
  else
    disconnect_connection(conn)
  end

  if opts.close_chat ~= false then
    pcall(function()
      chat:close()
    end)
  end

  return true
end

function M.suspend_current_chat(opts)
  local ok, chat_module = pcall(require, 'codecompanion.interactions.chat')
  if not ok then
    return false
  end

  local chat = chat_module.buf_get_chat(0)
  if not chat then
    return false
  end

  return M.suspend_chat(chat, opts)
end

local function open_chats()
  local ok, codecompanion = pcall(require, 'codecompanion')
  if not ok or type(codecompanion.buf_get_chat) ~= 'function' then
    return {}
  end

  local chats = {}
  for _, item in ipairs(codecompanion.buf_get_chat() or {}) do
    if item.chat then
      table.insert(chats, item.chat)
    end
  end
  return chats
end

local function connection_root_pid(chat)
  if not is_acp_chat(chat) or not chat.acp_connection then
    return nil
  end
  return remember_connection(chat.acp_connection)
end

function M.suspend_acp_chats(current_chat, opts)
  opts = opts or {}
  local include_current = opts.include_current == true
  local keep_root_pid = nil
  if not include_current then
    keep_root_pid = connection_root_pid(current_chat)
  end
  local sweep_tracked_roots = include_current
    or not is_acp_chat(current_chat)
    or keep_root_pid
  local result = {
    matched = 0,
    suspended = 0,
    already_disconnected = 0,
    killed_tracked_roots = 0,
    skipped_tracked_roots = false,
  }

  for _, chat in ipairs(open_chats()) do
    if is_acp_chat(chat) and (include_current or chat ~= current_chat) then
      result.matched = result.matched + 1
      if M.suspend_chat(chat, opts) then
        result.suspended = result.suspended + 1
      else
        result.already_disconnected = result.already_disconnected + 1
      end
    end
  end

  local root_pids = {}
  if sweep_tracked_roots then
    for root_pid in pairs(tracked) do
      if root_pid ~= keep_root_pid then
        table.insert(root_pids, root_pid)
      end
    end
  else
    result.skipped_tracked_roots = true
  end

  for _, root_pid in ipairs(root_pids) do
    kill_tracked_tree(root_pid, 15)
    result.killed_tracked_roots = result.killed_tracked_roots + 1
    vim.defer_fn(function()
      kill_tracked_tree(root_pid, 9)
      prune_tree(root_pid)
    end, 300)
  end

  return result
end

function M.suspend_other_acp_chats(current_chat, opts)
  opts = opts or {}
  opts.include_current = false
  return M.suspend_acp_chats(current_chat, opts)
end

function M.suspend_all_acp_chats(current_chat, opts)
  opts = opts or {}
  opts.include_current = true
  return M.suspend_acp_chats(current_chat, opts)
end

local function chat_is_visible(chat)
  if not (chat and chat.ui and type(chat.ui.is_visible) == 'function') then
    return false
  end

  local ok, visible = pcall(chat.ui.is_visible, chat.ui)
  return ok and visible == true
end

local function connection_has_session(conn)
  if not conn then
    return false
  end

  if type(conn.is_connected) == 'function' then
    local ok, connected = pcall(conn.is_connected, conn)
    if ok then
      return connected == true
    end
  end

  if type(conn.is_ready) ~= 'function' then
    return false
  end

  local ok, ready = pcall(conn.is_ready, conn)
  return ok and ready == true and conn.session_id ~= nil
end

function M.ensure_chat_connection(chat, cb, opts)
  cb = cb or function() end
  opts = opts or {}
  if not is_acp_chat(chat) then
    return false
  end

  local keep_visible = opts.keep_visible and chat_is_visible(chat)

  local function run_cb()
    if keep_visible and chat.ui and not chat_is_visible(chat) then
      pcall(chat.ui.open, chat.ui)
    end
    cb()
  end

  if connection_has_session(chat.acp_connection) then
    M.track_chat(chat)
    run_cb()
    return true
  end

  require('codecompanion.interactions.chat.helpers').create_acp_connection(
    chat,
    function()
      M.track_chat(chat)
      run_cb()
    end
  )
  return true
end

function M.close_disposable_chat(chat)
  if not is_acp_chat(chat) then
    return false
  end

  local ok, chat_fns = pcall(require, 'lpke.plugins.ai.helpers.chat_functions')
  if
    ok
    and chat.bufnr
    and api.nvim_buf_is_valid(chat.bufnr)
    and not chat_fns.is_empty_chat(chat.bufnr)
  then
    return false
  end

  pcall(function()
    chat:close()
  end)
  vim.notify('Disposable chat closed', vim.log.levels.INFO, {
    title = 'CodeCompanion',
  })
  return true
end

local function link_buffer_to_session(chat)
  local session_id = M.remember_session(chat)
  if not session_id then
    return
  end

  pcall(function()
    require('codecompanion.interactions.chat.acp.commands').link_buffer_to_session(
      chat.bufnr,
      session_id
    )
  end)
end

local chat_for_buf

local function guard_chat_visible(chat, ms)
  if not is_acp_chat(chat) or not chat_is_visible(chat) then
    return
  end

  local token = {}
  chat._lpke_keep_visible_token = token

  vim.defer_fn(function()
    if chat._lpke_keep_visible_token == token then
      chat._lpke_keep_visible_token = nil
    end
  end, ms or 2000)
end

local function patch_codecompanion()
  if patched then
    return
  end
  patched = true

  local ok_conn, Connection = pcall(require, 'codecompanion.acp')
  if ok_conn and not Connection._lpke_tree_disconnect then
    Connection._lpke_tree_disconnect = true

    local original_start = Connection.start_agent_process
    Connection.start_agent_process = function(self, ...)
      local ok = original_start(self, ...)
      if ok then
        remember_connection(self)
        vim.defer_fn(function()
          remember_connection(self)
        end, 250)
        vim.defer_fn(function()
          remember_connection(self)
        end, 1000)
      end
      return ok
    end

    local original_disconnect = Connection.disconnect
    Connection.disconnect = function(self, ...)
      local root_pid = remember_connection(self)
      if root_pid then
        kill_tracked_tree(root_pid, 15)
      end

      local _, result = pcall(original_disconnect, self, ...)

      if root_pid then
        vim.defer_fn(function()
          kill_tracked_tree(root_pid, 9)
          prune_tree(root_pid)
        end, 300)
      end

      return result
    end
  end

  local ok_handler, ACPHandler =
    pcall(require, 'codecompanion.interactions.chat.acp.handler')
  if ok_handler and not ACPHandler._lpke_resume_session then
    ACPHandler._lpke_resume_session = true

    local original_ensure_session = ACPHandler.ensure_session
    ACPHandler.ensure_session = function(self, ...)
      local chat = self.chat
      local conn = chat and chat.acp_connection
      local session_id = saved_session_id(chat)

      if
        conn
        and not conn.session_id
        and session_id
        and conn:is_ready()
        and conn:can_load_session()
      then
        local ok, loaded = pcall(function()
          return conn:load_session(session_id)
        end)
        if ok and loaded then
          link_buffer_to_session(chat)
          pcall(function()
            chat:update_metadata()
          end)
          M.track_chat(chat)
          vim.notify('ACP session resumed', vim.log.levels.INFO, {
            title = 'CodeCompanion',
          })
          return true
        end
      end

      local ok = original_ensure_session(self, ...)
      if ok then
        link_buffer_to_session(chat)
        M.track_chat(chat)
      end
      return ok
    end
  end

  local ok_ui, ChatUI = pcall(require, 'codecompanion.interactions.chat.ui')
  if ok_ui and not ChatUI._lpke_keep_visible_guard then
    ChatUI._lpke_keep_visible_guard = true

    local original_hide = ChatUI.hide
    ChatUI.hide = function(self, ...)
      local chat = chat_for_buf and chat_for_buf(self.chat_bufnr)
      if chat and chat._lpke_keep_visible_token and chat_is_visible(chat) then
        return
      end

      return original_hide(self, ...)
    end
  end

  local ok_session_options, SessionOptions = pcall(
    require,
    'codecompanion.interactions.chat.slash_commands.builtin.acp_session_options'
  )
  if ok_session_options and not SessionOptions._lpke_ensure_connection then
    SessionOptions._lpke_ensure_connection = true

    local original_show_values = SessionOptions.show_values
    SessionOptions.show_values = function(self, ...)
      guard_chat_visible(self.Chat)
      return original_show_values(self, ...)
    end

    local original_execute = SessionOptions.execute
    SessionOptions.execute = function(self, ...)
      local args = { ... }
      guard_chat_visible(self.Chat)

      vim.schedule(function()
        local chat = chat_for_buf(0)
        if not is_acp_chat(chat) then
          chat = self.Chat
        end

        if not is_acp_chat(chat) then
          return original_execute(self, unpack(args))
        end

        self.Chat = chat
        guard_chat_visible(chat)
        M.ensure_chat_connection(chat, function()
          self.Chat = chat
          guard_chat_visible(chat)
          original_execute(self, unpack(args))
        end, {
          keep_visible = true,
        })
      end)

      return true
    end
  end
end

chat_for_buf = function(bufnr)
  local ok, chat_module = pcall(require, 'codecompanion.interactions.chat')
  if not ok then
    return nil
  end
  return chat_module.buf_get_chat(bufnr)
end

local function scan_open_chats()
  for _, chat in ipairs(open_chats()) do
    if is_acp_chat(chat) then
      M.track_chat(chat)
    end
  end
end

function M.setup()
  patch_codecompanion()
  local killed = M.cleanup_stale_orphans()
  if killed > 0 then
    vim.notify(
      string.format(
        'Killed %d stale ACP process%s',
        killed,
        killed == 1 and '' or 'es'
      ),
      vim.log.levels.INFO,
      { title = 'CodeCompanion' }
    )
  end

  api.nvim_create_autocmd('User', {
    group = augroup,
    pattern = 'CodeCompanionChatCreated',
    callback = function(args)
      local chat = chat_for_buf(args.data and args.data.bufnr)
      if not is_acp_chat(chat) then
        return
      end
      if vim.g.lpke_cc_chat_create_notified then
        vim.g.lpke_cc_chat_create_notified = nil
        return
      end
      vim.notify('ACP chat created', vim.log.levels.INFO, {
        title = 'CodeCompanion',
      })

      vim.defer_fn(function()
        M.track_chat(chat)
      end, 500)
    end,
  })

  api.nvim_create_autocmd('User', {
    group = augroup,
    pattern = {
      'CodeCompanionACPConnected',
      'CodeCompanionACPSessionPost',
    },
    callback = function(args)
      local chat = args.data
        and args.data.bufnr
        and chat_for_buf(args.data.bufnr)
      if chat then
        M.track_chat(chat)
      else
        scan_open_chats()
      end
    end,
  })

  api.nvim_create_autocmd('VimLeavePre', {
    group = augroup,
    callback = function()
      scan_open_chats()
      for root_pid in pairs(tracked) do
        kill_tracked_tree(root_pid, 15)
      end
      for root_pid in pairs(tracked) do
        kill_tracked_tree(root_pid, 9)
      end
    end,
  })
end

return M
