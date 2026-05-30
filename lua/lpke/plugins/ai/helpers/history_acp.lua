local M = {}

local patched = false

local function is_acp_chat(chat)
  return chat and chat.adapter and chat.adapter.type == 'acp'
end

local function session_id_from_chat(chat)
  return chat
    and (
      chat.acp_session_id
      or (chat.opts and chat.opts.acp_session_id)
      or (chat.acp_connection and chat.acp_connection.session_id)
    )
end

function M.short_session_id(session_id)
  if type(session_id) ~= 'string' or session_id == '' then
    return nil
  end

  if #session_id <= 4 then
    return session_id
  end

  return session_id:sub(-4)
end

function M.format_session_id(session_id)
  local short = M.short_session_id(session_id)
  return short and ('[' .. short .. ']') or nil
end

function M.format_session_kind(session_id, kind)
  local short = M.short_session_id(session_id)
  if short then
    return '[' .. short .. '] [' .. kind .. ']'
  end
  return '[' .. kind .. ']'
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

local function find_open_chat_by_save_id(save_id)
  if type(save_id) ~= 'string' or save_id == '' then
    return nil
  end

  for _, chat in ipairs(open_chats()) do
    if chat.opts and chat.opts.save_id == save_id then
      return chat
    end
  end
end

local function remember_chat_session(chat)
  if not is_acp_chat(chat) then
    return nil
  end

  local session_id = session_id_from_chat(chat)
  if not session_id then
    return nil
  end

  chat.acp_session_id = session_id
  chat.opts = chat.opts or {}
  chat.opts.acp_session_id = session_id
  return session_id
end

local function enrich_chat_data(chat_data)
  if type(chat_data) ~= 'table' then
    return chat_data
  end

  if
    type(chat_data.acp_session_id) == 'string'
    and chat_data.acp_session_id ~= ''
  then
    return chat_data
  end

  local chat = find_open_chat_by_save_id(chat_data.save_id)
  local session_id = remember_chat_session(chat)
  if session_id then
    chat_data.acp_session_id = session_id
  end

  return chat_data
end

local function chat_has_visible_user_content(chat)
  for _, msg in ipairs(chat.messages or {}) do
    if
      msg.role == 'user'
      and not (msg.opts and msg.opts.visible == false)
      and type(msg.content) == 'string'
      and vim.trim(msg.content) ~= ''
    then
      return true
    end
  end

  return false
end

local function save_acp_chat(chat)
  if not is_acp_chat(chat) or not remember_chat_session(chat) then
    return
  end

  if not chat_has_visible_user_content(chat) then
    return
  end

  local ok, history = pcall(function()
    return require('codecompanion').extensions.history
  end)
  if ok and history and type(history.save_chat) == 'function' then
    history.save_chat(chat)
  end
end

local function save_open_acp_chats()
  for _, chat in ipairs(open_chats()) do
    save_acp_chat(chat)
  end
end

local function with_session_marker(title, session_id)
  local marker = M.format_session_id(session_id)
  if not marker then
    return title
  end

  if title:find(marker, 1, true) then
    return title
  end

  return marker .. ' ' .. title
end

local function is_acp_history_chat(chat_data)
  if
    type(chat_data) ~= 'table'
    or type(chat_data.acp_session_id) ~= 'string'
    or chat_data.acp_session_id == ''
  then
    return false
  end

  local ok, adapter =
    pcall(require('codecompanion.adapters').resolve, chat_data.adapter)
  return ok and adapter and adapter.type == 'acp'
end

local function set_chat_session(chat, session_id)
  if not chat or type(session_id) ~= 'string' or session_id == '' then
    return
  end

  chat.acp_session_id = session_id
  chat.opts = chat.opts or {}
  chat.opts.acp_session_id = session_id
end

function M.resume_session_into_chat(chat, session, opts)
  opts = opts or {}
  local session_id = type(session) == 'table' and session.sessionId or session

  if type(session_id) ~= 'string' or session_id == '' then
    return false, 'Missing ACP session ID'
  end

  if not is_acp_chat(chat) then
    return false, 'Selected chat is not using an ACP adapter'
  end

  local conn = chat.acp_connection
  if
    not conn
    or not conn.can_load_session
    or not conn:can_load_session()
    or not conn.load_session
  then
    return false, 'ACP adapter cannot load sessions'
  end

  local updates = {}
  local ok, loaded = pcall(conn.load_session, conn, session_id, {
    on_session_update = function(update)
      table.insert(updates, update)
    end,
  })

  if not ok then
    return false, loaded
  end

  if not loaded then
    return false, 'Failed to load ACP session'
  end

  require('codecompanion.interactions.chat.acp.commands').link_buffer_to_session(
    chat.bufnr,
    conn.session_id
  )

  require('codecompanion.interactions.chat.acp.render').restore_session(
    chat,
    updates
  )
  chat._lpke_acp_session_restored = session_id
  chat._lpke_restore_acp_session_updates = nil

  if type(session) == 'table' and session.title then
    chat:set_title(session.title)
  elseif opts.title then
    chat:set_title(opts.title)
  end

  local ok_lifecycle, lifecycle =
    pcall(require, 'lpke.plugins.ai.helpers.acp_lifecycle')
  if ok_lifecycle and lifecycle.remember_session then
    lifecycle.remember_session(chat)
  else
    set_chat_session(chat, session_id)
  end

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'CodeCompanionACPChatRestored',
    data = {
      bufnr = chat.bufnr,
      id = chat.id,
      session_id = conn.session_id,
      title = chat.title,
    },
  })

  vim.notify('ACP session resumed', vim.log.levels.INFO, {
    title = 'CodeCompanion',
  })

  return true
end

local function current_chat()
  local ok_chat, chat_module = pcall(require, 'codecompanion.interactions.chat')
  if ok_chat then
    local chat = chat_module.buf_get_chat(0)
    if chat then
      return chat
    end
  end

  local ok_codecompanion, codecompanion = pcall(require, 'codecompanion')
  if ok_codecompanion and type(codecompanion.last_chat) == 'function' then
    return codecompanion.last_chat()
  end
end

local function find_acp_session(chat, session)
  local conn = chat and chat.acp_connection
  if not conn or not conn.can_list_sessions or not conn:can_list_sessions() then
    return nil, 'ACP adapter cannot list sessions'
  end

  local ok, sessions = pcall(conn.session_list, conn, {
    max_sessions = 500,
  })
  if not ok then
    return nil, sessions
  end

  for _, item in ipairs(sessions or {}) do
    if item.sessionId == session.sessionId then
      return item
    end
  end

  return nil, 'ACP session not found in resume list'
end

local function with_acp_connection(chat, cb)
  if
    chat.acp_connection
    and chat.acp_connection.is_ready
    and chat.acp_connection:is_ready()
  then
    cb(chat)
    return
  end

  require('codecompanion.interactions.chat.helpers').create_acp_connection(
    chat,
    function()
      cb(chat)
    end
  )
end

local function open_acp_resume_chat(source_chat, cb)
  if source_chat and source_chat.ui then
    pcall(function()
      source_chat.ui:hide()
    end)
  end

  vim.g.lpke_cc_chat_create_notified = true
  vim.cmd('CodeCompanionChat')

  local chat = require('codecompanion.interactions.chat').buf_get_chat(0)
  if not chat then
    return nil
  end

  local adapter =
    require('lpke.plugins.ai.helpers.config').defaults.chat_adapter
  if chat.adapter and chat.adapter.type == 'acp' then
    cb(chat)
    return chat
  end

  chat:change_adapter(adapter, function()
    require('lpke.plugins.ai.helpers.chat_functions').remove_http_tool_context(
      chat.bufnr
    )
    cb(chat)
  end)

  return chat
end

local function fallback_after_resume_failure(fallback, err)
  vim.notify(
    tostring(err or 'ACP resume failed') .. '; opened saved history chat',
    vim.log.levels.ERROR,
    { title = 'CodeCompanion' }
  )

  if fallback then
    fallback()
  end
end

function M.resume_session_from_history(chat_data, fallback)
  if not is_acp_history_chat(chat_data) then
    return false
  end

  local session = {
    sessionId = chat_data.acp_session_id,
    title = chat_data.title,
  }

  local function resume_into(chat)
    with_acp_connection(chat, function(target_chat)
      local selected, find_err = find_acp_session(target_chat, session)
      if not selected then
        fallback_after_resume_failure(fallback, find_err)
        return
      end

      local ok, resume_err = M.resume_session_into_chat(target_chat, selected)
      if not ok then
        fallback_after_resume_failure(fallback, resume_err)
      end
    end)
  end

  local source_chat = current_chat()
  if is_acp_chat(source_chat) then
    resume_into(source_chat)
    return true
  end

  if not open_acp_resume_chat(source_chat, resume_into) then
    fallback_after_resume_failure(fallback, 'Failed to open ACP resume chat')
  end

  return true
end

function M.resume_history_chat(ui, chat_data, fallback)
  return M.resume_session_from_history(chat_data, fallback)
end

local function patch_storage()
  local ok, Storage =
    pcall(require, 'codecompanion._extensions.history.storage')
  if not ok or Storage._lpke_acp_session_ids then
    return
  end
  Storage._lpke_acp_session_ids = true

  local original_save_chat_to_file = Storage._save_chat_to_file
  Storage._save_chat_to_file = function(self, chat_data, ...)
    return original_save_chat_to_file(self, enrich_chat_data(chat_data), ...)
  end

  local original_update_index_entry = Storage._update_index_entry
  Storage._update_index_entry = function(self, chat_data, ...)
    chat_data = enrich_chat_data(chat_data)
    local result = original_update_index_entry(self, chat_data, ...)

    if
      result
      and result.ok
      and type(chat_data.acp_session_id) == 'string'
      and chat_data.acp_session_id ~= ''
    then
      local utils = require('codecompanion._extensions.history.utils')
      local index_result = utils.read_json(self.index_path)
      if index_result.ok then
        local index = index_result.data or {}
        index[chat_data.save_id] = index[chat_data.save_id] or {}
        index[chat_data.save_id].acp_session_id = chat_data.acp_session_id
        return utils.write_json(self.index_path, utils.remove_functions(index))
      end
    end

    return result
  end

  local original_get_chats = Storage.get_chats
  Storage.get_chats = function(self, filter_fn, ...)
    local chats = original_get_chats(self, filter_fn, ...)
    for save_id, meta in pairs(chats or {}) do
      if type(meta) == 'table' and not meta.acp_session_id then
        local chat_data = self:load_chat(save_id)
        if chat_data and chat_data.acp_session_id then
          meta.acp_session_id = chat_data.acp_session_id
        end
      end
    end
    return chats
  end
end

local function patch_history_ui()
  local ok, UI = pcall(require, 'codecompanion._extensions.history.ui')
  if not ok then
    return
  end
  UI._lpke_acp_session_ids = true

  if not UI._lpke_acp_create_chat then
    UI._lpke_acp_create_chat = true

    local original_create_chat = UI.create_chat
    UI.create_chat = function(self, chat_data, ...)
      local chat = original_create_chat(self, chat_data, ...)
      if chat and chat_data and chat_data.acp_session_id then
        chat.acp_session_id = chat_data.acp_session_id
        chat.opts = chat.opts or {}
        chat.opts.acp_session_id = chat_data.acp_session_id
      end
      return chat
    end
  end

  if not UI._lpke_acp_resume_history then
    UI._lpke_acp_resume_history = true

    local original_handle_on_select = UI._handle_on_select
    UI._handle_on_select = function(self, save_id, ...)
      local args = { ... }
      local chat_data = self.storage and self.storage:load_chat(save_id)
      local fallback = function()
        original_handle_on_select(self, save_id, unpack(args))
      end

      if chat_data and M.resume_history_chat(self, chat_data, fallback) then
        return
      end

      return fallback()
    end
  end
end

local function patch_history_picker()
  local ok, DefaultPicker =
    pcall(require, 'codecompanion._extensions.history.pickers.default')
  if not ok or DefaultPicker._lpke_acp_session_ids then
    return
  end
  DefaultPicker._lpke_acp_session_ids = true

  local original_get_item_title = DefaultPicker.get_item_title
  DefaultPicker.get_item_title = function(self, item, ...)
    local title = original_get_item_title(self, item, ...)
    if self.config and self.config.item_type == 'chat' then
      return with_session_marker(title, item and item.acp_session_id)
    end
    return title
  end
end

local function setup_autocmds()
  local group = vim.api.nvim_create_augroup('LpkeCodeCompanionHistoryACP', {
    clear = true,
  })

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = {
      'CodeCompanionACPSessionPost',
      'CodeCompanionACPChatRestored',
      'CodeCompanionRequestFinished',
    },
    callback = function()
      vim.defer_fn(save_open_acp_chats, 100)
    end,
  })
end

function M.setup()
  if patched then
    return
  end
  patched = true

  patch_storage()
  patch_history_ui()
  patch_history_picker()
  setup_autocmds()
end

return M
