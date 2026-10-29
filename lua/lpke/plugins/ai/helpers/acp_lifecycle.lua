local M = {}

local api = vim.api
local processes = require('lpke.plugins.ai.helpers.acp_process')
local registry = require('lpke.plugins.ai.helpers.chat_registry')
local chat_for_buf = registry.get
local unpack = unpack or table.unpack

local augroup = api.nvim_create_augroup('LpkeCodeCompanionACPLifecycle', {
  clear = true,
})

local patched = false

local function is_acp_chat(chat)
  return chat and chat.adapter and chat.adapter.type == 'acp'
end

local saved_session_id = registry.session_id

local function saved_cwd(chat)
  if not chat then
    return nil
  end

  local candidates = {
    chat.opts and chat.opts.cwd,
    chat.cwd,
    chat.project_root,
    chat.opts and chat.opts.project_root,
  }
  for index = 1, 4 do
    local cwd = candidates[index]
    local stat = type(cwd) == 'string' and cwd ~= '' and vim.uv.fs_stat(cwd)
    if stat and stat.type == 'directory' then
      return cwd
    end
  end
end

local function set_connection_cwd(chat)
  if not is_acp_chat(chat) or not chat.acp_connection then
    return
  end

  chat.acp_connection._lpke_cwd = saved_cwd(chat)
end

local function acp_session_args(conn)
  local defaults = conn.adapter_modified and conn.adapter_modified.defaults
    or {}
  local mcp_servers = defaults.mcpServers

  if mcp_servers == 'inherit_from_config' then
    local ok_config, config = pcall(require, 'codecompanion.config')
    if
      ok_config
      and config.mcp
      and config.mcp.opts
      and config.mcp.opts.acp_enabled
    then
      local ok_mcp, mcp = pcall(require, 'codecompanion.mcp')
      if ok_mcp then
        mcp_servers = mcp.transform_to_acp()
      end
    end
  end

  return {
    cwd = vim.fn.getcwd(),
    mcpServers = mcp_servers,
  }
end

local function exact_load_session(conn, session_id, opts)
  opts = opts or {}
  if
    not conn
    or type(conn.is_ready) ~= 'function'
    or not conn:is_ready()
    or type(conn.send_rpc_request) ~= 'function'
  then
    return false
  end

  local previous_session_id = conn.session_id
  local previous_loading_session = conn._loading_session
  local previous_on_session_update = conn._on_session_update

  conn._lpke_session_load_error = nil
  conn.session_id = session_id
  conn._loading_session = true
  conn._on_session_update = opts.on_session_update

  local ok, loaded_session = pcall(
    conn.send_rpc_request,
    conn,
    conn.METHODS.SESSION_LOAD,
    vim.tbl_extend('force', acp_session_args(conn), {
      sessionId = session_id,
    })
  )

  conn._loading_session = previous_loading_session
  conn._on_session_update = previous_on_session_update
  local load_error = conn._lpke_session_load_error
  conn._lpke_session_load_error = nil

  if not ok or not loaded_session then
    conn.session_id = previous_session_id
    return false,
      not ok and tostring(loaded_session)
        or load_error
        or 'Failed to load ACP session'
  end

  if
    loaded_session.configOptions
    and type(conn._apply_config_options) == 'function'
  then
    conn:_apply_config_options(loaded_session.configOptions)
  end

  require('codecompanion.interactions.chat.acp.defaults').apply(
    conn.adapter,
    conn
  )

  return true
end

local function set_saved_session_id(chat, session_id)
  if not is_acp_chat(chat) then
    return
  end

  chat.acp_session_id = session_id
  chat.opts = chat.opts or {}
  chat.opts.acp_session_id = session_id
end

function M.remember_session(chat)
  if not is_acp_chat(chat) then
    return nil
  end

  local session_id = saved_session_id(chat)
  if not session_id then
    return nil
  end

  set_saved_session_id(chat, session_id)
  return session_id
end

M.get_session_id = registry.session_id

local function owns_connection(chat, conn)
  return chat.acp_connection == conn and api.nvim_buf_is_valid(chat.bufnr)
end

local function run_session_step(chat, conn, work, serial)
  -- A load may run on the main loop and pump callbacks while waiting for RPC.
  -- Another explicit load in a callback cannot wait for that outer call to
  -- unwind. Readiness consumers can still share the current transaction.
  if serial and conn._in_flight and conn._in_flight.lpke_session_ready then
    return false, 'ACP session is busy; wait for it to finish before resuming'
  end
  local failure
  local function guarded_work()
    if not owns_connection(chat, conn) then
      failure = 'ACP connection changed while preparing the session'
      return false
    end
    local token = {}
    chat._lpke_session_preparing = token
    local ok, result, err = pcall(work)
    if chat._lpke_session_preparing == token then
      chat._lpke_session_preparing = nil
    end
    if ok then
      failure = err
    else
      failure = result
    end
    return ok and result and owns_connection(chat, conn) or false
  end
  local success
  if conn._run_once then
    success = conn:_run_once({
      key = 'lpke_session_ready',
      work = guarded_work,
    })
  else
    success = guarded_work()
  end
  return success, failure
end

function M.is_preparing(chat)
  if not is_acp_chat(chat) then
    return false
  end
  if chat._lpke_session_preparing then
    return true
  end
  if saved_session_id(chat) then
    local conn = chat.acp_connection
    if conn and type(conn.is_connected) == 'function' then
      return not conn:is_connected()
    end
    return not conn or not conn.session_id
  end
  return false
end

function M.load_session(chat, session_id, opts)
  if
    not is_acp_chat(chat)
    or type(session_id) ~= 'string'
    or session_id == ''
  then
    return false
  end

  local conn = chat.acp_connection
  if not conn then
    return false
  end

  opts = opts or {}
  return run_session_step(chat, conn, function()
    if not conn:can_load_session() then
      return false, 'ACP adapter cannot load sessions'
    end
    set_connection_cwd(chat)
    local loaded, err = exact_load_session(conn, session_id, opts)
    if not loaded or conn.session_id ~= session_id then
      return false, err
    end
    if not owns_connection(chat, conn) then
      return false, 'ACP connection changed while loading the session'
    end
    if opts.after_load then
      opts.after_load()
    end
    return true
  end, true)
end

function M.track_chat(chat)
  if not is_acp_chat(chat) or not chat.acp_connection then
    return
  end

  set_connection_cwd(chat)
  M.remember_session(chat)
  processes.observe(chat.acp_connection)
end

function M.cleanup_stale_orphans()
  return processes.cleanup_orphans(vim.fn.getcwd())
end

local function disconnect_connection(conn)
  if conn then
    pcall(conn.disconnect, conn)
  end
end

function M.suspend_chat(chat, opts)
  opts = opts or {}
  if not is_acp_chat(chat) or not chat.acp_connection then
    return false
  end

  local conn = chat.acp_connection
  M.remember_session(chat)
  processes.observe(conn)

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
  local chat = registry.get()
  return chat and M.suspend_chat(chat, opts) or false
end

function M.suspend_acp_chats(current_chat, opts)
  opts = opts or {}
  local include_current = opts.include_current == true
  local keep_root_pid = nil
  if not include_current then
    keep_root_pid = processes.pid(current_chat and current_chat.acp_connection)
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

  for _, chat in ipairs(registry.list()) do
    if is_acp_chat(chat) and (include_current or chat ~= current_chat) then
      result.matched = result.matched + 1
      if M.suspend_chat(chat, opts) then
        result.suspended = result.suspended + 1
      else
        result.already_disconnected = result.already_disconnected + 1
      end
    end
  end

  if sweep_tracked_roots then
    result.killed_tracked_roots = processes.stop_tracked(keep_root_pid)
  else
    result.skipped_tracked_roots = true
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

local function readiness_callback(chat, conn, callback, session_required)
  local adapter = chat.adapter
  return function()
    if
      is_acp_chat(chat)
      and chat.adapter == adapter
      and owns_connection(chat, conn)
      and conn:is_ready()
      and not chat._lpke_session_preparing
      and (not session_required or connection_has_session(conn))
    then
      return callback()
    end
  end
end

function M.ensure_chat_connection(chat, cb, opts)
  cb = cb or function() end
  opts = opts or {}
  if not is_acp_chat(chat) then
    return false
  end

  if not chat.acp_connection then
    chat.acp_connection = require('codecompanion.acp').new({
      adapter = chat.adapter,
      chat = chat,
    })
  end
  local conn = chat.acp_connection

  local keep_visible = opts.keep_visible and chat_is_visible(chat)

  local run_cb = readiness_callback(chat, conn, function()
    if keep_visible and chat.ui and not chat_is_visible(chat) then
      pcall(chat.ui.open, chat.ui)
    end
    cb()
  end, true)

  if
    connection_has_session(chat.acp_connection) and not M.is_preparing(chat)
  then
    set_connection_cwd(chat)
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

function M.ensure_chat_ready(chat, cb)
  cb = cb or function() end
  if not is_acp_chat(chat) then
    return false
  end

  if not chat.acp_connection then
    chat.acp_connection = require('codecompanion.acp').new({
      adapter = chat.adapter,
      chat = chat,
    })
  end
  local conn = chat.acp_connection
  local guarded_cb = readiness_callback(chat, conn, cb)
  local function run_cb()
    if not owns_connection(chat, conn) then
      return
    end
    if chat._lpke_session_preparing then
      require('codecompanion.interactions.chat.helpers').create_acp_connection(
        chat,
        guarded_cb
      )
      return
    end
    guarded_cb()
  end

  if
    chat.acp_connection
    and type(chat.acp_connection.is_ready) == 'function'
    and chat.acp_connection:is_ready()
  then
    set_connection_cwd(chat)
    M.track_chat(chat)
    run_cb()
    return true
  end

  set_connection_cwd(chat)

  require('codecompanion.utils.async').sync(function()
    local handler =
      require('codecompanion.interactions.chat.acp.handler').new(chat)
    if handler:ensure_connection() then
      M.track_chat(chat)
    end
    vim.schedule(run_cb)
  end)()

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

local function notify_acp_session_unavailable(chat, err)
  local message = 'ACP session unavailable; opened saved history chat'
  if err then
    message = message .. ': ' .. tostring(err)
  end
  if chat._lpke_acp_session_unavailable_notified == message then
    return
  end
  chat._lpke_acp_session_unavailable_notified = message

  vim.notify(message, vim.log.levels.WARN, { title = 'CodeCompanion' })
end

local function patch_codecompanion()
  if patched then
    return
  end
  patched = true

  local ok_conn, Connection = pcall(require, 'codecompanion.acp')
  if ok_conn then
    processes.patch(Connection)
  end
  if ok_conn and not Connection._lpke_session_context then
    Connection._lpke_session_context = true

    -- Upstream discards RPC errors when resuming the waiting coroutine.
    local original_store_rpc_response = Connection.store_rpc_response
    Connection.store_rpc_response = function(self, response)
      if self._loading_session and response.error then
        self._lpke_session_load_error = response.error.message
      end
      return original_store_rpc_response(self, response)
    end

    local original_start = Connection.start_agent_process
    Connection.start_agent_process = function(self, ...)
      local cwd = self._lpke_cwd
      if type(cwd) ~= 'string' or cwd == '' then
        return original_start(self, ...)
      end

      local job = self.methods.job
      self.methods.job = function(cmd, opts, cb)
        opts = opts or {}
        opts.cwd = cwd
        return job(cmd, opts, cb)
      end

      local ok, result = pcall(original_start, self, ...)
      self.methods.job = job
      if not ok then
        error(result)
      end
      return result
    end

    local original_send_rpc_request = Connection.send_rpc_request
    Connection.send_rpc_request = function(self, method, params, ...)
      local cwd = self._lpke_cwd
      if
        type(cwd) == 'string'
        and cwd ~= ''
        and type(params) == 'table'
        and (
          method == self.METHODS.SESSION_LIST
          or method == self.METHODS.SESSION_LOAD
          or method == self.METHODS.SESSION_NEW
        )
      then
        params = vim.tbl_extend('force', params, { cwd = cwd })
      end

      return original_send_rpc_request(self, method, params, ...)
    end
  end

  local ok_handler, ACPHandler =
    pcall(require, 'codecompanion.interactions.chat.acp.handler')
  if ok_handler and not ACPHandler._lpke_resume_session then
    ACPHandler._lpke_resume_session = true

    local original_ensure_session = ACPHandler.ensure_session
    local function ensure_session(self, ...)
      local chat = self.chat
      local conn = chat and chat.acp_connection
      local session_id = saved_session_id(chat)

      set_connection_cwd(chat)

      if
        chat
        and conn
        and not conn.session_id
        and (
          (chat.opts and chat.opts.acp_connection_only)
          or (chat._lpke_acp_connection_only and not session_id)
        )
      then
        return true
      end

      if conn and not conn.session_id and session_id and conn:is_ready() then
        if not conn:can_load_session() then
          notify_acp_session_unavailable(
            chat,
            'ACP agent does not support loading saved sessions'
          )
          return false
        end
        local updates = {}
        local should_restore = chat._lpke_restore_acp_session_updates
            == session_id
          or (
            chat.opts and (chat.opts.save_id or chat.opts.restore_acp_session)
          )
        local load_opts = should_restore
            and {
              on_session_update = function(update)
                table.insert(updates, update)
              end,
            }
          or nil

        local ok, loaded, err =
          pcall(exact_load_session, conn, session_id, load_opts)
        if
          chat.acp_connection ~= conn or not api.nvim_buf_is_valid(chat.bufnr)
        then
          return false
        end
        if ok and loaded and conn.session_id == session_id then
          chat._lpke_acp_session_unavailable_notified = nil
          link_buffer_to_session(chat)
          if should_restore and #updates > 0 then
            require('lpke.plugins.ai.helpers.chat_replay').restore(
              chat,
              updates
            )
            chat._lpke_acp_session_restored = session_id
          end
          chat._lpke_restore_acp_session_updates = nil
          pcall(function()
            chat:update_metadata()
          end)
          M.track_chat(chat)
          if should_restore then
            vim.api.nvim_exec_autocmds('User', {
              pattern = 'CodeCompanionACPChatRestored',
              data = {
                bufnr = chat.bufnr,
                id = chat.id,
                session_id = conn.session_id,
                title = chat.title,
              },
            })
          end
          vim.notify('ACP session resumed', vim.log.levels.INFO, {
            title = 'CodeCompanion',
          })
          return true
        end

        -- Keep the saved ID so a retry resumes this thread. Returning success
        -- here allowed later submissions to create an unrelated session.
        notify_acp_session_unavailable(chat, ok and err or loaded)
        return false
      end

      local ok = original_ensure_session(self, ...)
      if chat.acp_connection ~= conn then
        return false
      end
      if ok then
        link_buffer_to_session(chat)
        M.track_chat(chat)
      end
      return ok
    end

    ACPHandler.ensure_session = function(self, ...)
      local chat = self.chat
      local conn = chat and chat.acp_connection
      if not conn then
        return false
      end
      local args = { ... }
      -- The native step shares one result with concurrent callers. Keep the
      -- entire default/load/replay transaction inside it, not just session/new.
      return run_session_step(chat, conn, function()
        return ensure_session(self, unpack(args))
      end)
    end

    local original_ensure_connection = ACPHandler.ensure_connection
    ACPHandler.ensure_connection = function(self, ...)
      local chat = self.chat
      if chat and not api.nvim_buf_is_valid(chat.bufnr) then
        return false
      end
      if is_acp_chat(chat) and not chat.acp_connection then
        chat.acp_connection = require('codecompanion.acp').new({
          adapter = chat.adapter,
          chat = chat,
        })
      end
      set_connection_cwd(chat)
      return original_ensure_connection(self, ...)
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

local function scan_open_chats()
  for _, chat in ipairs(registry.list()) do
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
      processes.finish()
    end,
  })
end

return M
