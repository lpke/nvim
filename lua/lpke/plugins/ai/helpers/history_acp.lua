local M = {}

local patched = false

local function is_acp_chat(chat)
  return chat and chat.adapter and chat.adapter.type == 'acp'
end

local function session_id_from_chat(chat)
  return chat
    and (
      (chat.acp_connection and chat.acp_connection.session_id)
      or chat.acp_session_id
      or (chat.opts and chat.opts.acp_session_id)
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

local function open_chat(chat)
  if not (chat and chat.ui and type(chat.ui.open) == 'function') then
    return false
  end

  local ok_codecompanion, codecompanion = pcall(require, 'codecompanion')
  local active_chat = ok_codecompanion
      and type(codecompanion.last_chat) == 'function'
      and codecompanion.last_chat()
    or nil

  if active_chat and active_chat ~= chat and active_chat.ui then
    pcall(function()
      active_chat.ui:hide()
    end)
  end

  local ok = pcall(function()
    chat.ui:open()
  end)

  return ok
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

local function find_open_chat_by_session_id(session_id)
  if type(session_id) ~= 'string' or session_id == '' then
    return nil
  end

  for _, chat in ipairs(open_chats()) do
    if is_acp_chat(chat) and session_id_from_chat(chat) == session_id then
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

local function read_index(storage)
  local ok, utils = pcall(require, 'codecompanion._extensions.history.utils')
  if not ok then
    return nil, nil
  end

  local result = utils.read_json(storage.index_path)
  if not result.ok then
    return nil, utils
  end

  return result.data or {}, utils
end

local function canonical_save_id_for_session(
  storage,
  session_id,
  current_save_id
)
  if type(session_id) ~= 'string' or session_id == '' then
    return current_save_id
  end

  local index = read_index(storage)
  if not index then
    return current_save_id
  end

  local canonical_id = nil
  local canonical_updated_at = nil
  for save_id, meta in pairs(index) do
    if
      type(meta) == 'table'
      and meta.acp_session_id == session_id
      and type(save_id) == 'string'
    then
      local updated_at = tonumber(meta.updated_at) or 0
      if
        not canonical_id
        or updated_at > canonical_updated_at
        or (updated_at == canonical_updated_at and save_id < canonical_id)
      then
        canonical_id = save_id
        canonical_updated_at = updated_at
      end
    end
  end

  return canonical_id or current_save_id
end

local function delete_chat_file(storage, save_id)
  if type(save_id) ~= 'string' or save_id == '' then
    return
  end

  local ok, utils = pcall(require, 'codecompanion._extensions.history.utils')
  if ok then
    utils.delete_file(storage.chats_dir .. '/' .. save_id .. '.json')
  end
end

local function compact_acp_session_index(storage, target_session_id)
  local index, utils = read_index(storage)
  if not index or not utils then
    return
  end

  local by_session = {}
  for save_id, meta in pairs(index) do
    if
      type(save_id) == 'string'
      and type(meta) == 'table'
      and type(meta.acp_session_id) == 'string'
      and meta.acp_session_id ~= ''
      and (not target_session_id or meta.acp_session_id == target_session_id)
    then
      local session_id = meta.acp_session_id
      by_session[session_id] = by_session[session_id] or {}
      table.insert(by_session[session_id], {
        save_id = save_id,
        updated_at = tonumber(meta.updated_at) or 0,
      })
    end
  end

  local changed = false
  for _, entries in pairs(by_session) do
    if #entries > 1 then
      table.sort(entries, function(a, b)
        if a.updated_at == b.updated_at then
          return a.save_id < b.save_id
        end
        return a.updated_at > b.updated_at
      end)

      for i = 2, #entries do
        local save_id = entries[i].save_id
        index[save_id] = nil
        delete_chat_file(storage, save_id)
        changed = true
      end
    end
  end

  if changed then
    utils.write_json(storage.index_path, utils.remove_functions(index))
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
  local restore_context = opts.restore_context
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
  local load_opts = {
    on_session_update = function(update)
      table.insert(updates, update)
    end,
  }
  local ok_lifecycle, lifecycle =
    pcall(require, 'lpke.plugins.ai.helpers.acp_lifecycle')
  local ok, loaded
  if ok_lifecycle and type(lifecycle.load_session) == 'function' then
    ok, loaded = pcall(lifecycle.load_session, chat, session_id, load_opts)
  else
    ok, loaded = pcall(conn.load_session, conn, session_id, load_opts)
  end

  if not ok then
    return false, loaded
  end

  if not loaded then
    return false, 'Failed to load ACP session'
  end

  if conn.session_id ~= session_id then
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

  local ok_chat_fns, chat_fns =
    pcall(require, 'lpke.plugins.ai.helpers.chat_functions')
  if ok_chat_fns then
    chat_fns.after_restore(chat, restore_context)
  end

  return true
end

local function patch_storage()
  local ok, Storage =
    pcall(require, 'codecompanion._extensions.history.storage')
  if not ok or Storage._lpke_acp_session_ids then
    return
  end
  Storage._lpke_acp_session_ids = true

  local original_save_chat = Storage.save_chat
  Storage.save_chat = function(self, chat, ...)
    if is_acp_chat(chat) then
      local session_id = remember_chat_session(chat)
      if session_id then
        chat.opts = chat.opts or {}
        chat.opts.save_id =
          canonical_save_id_for_session(self, session_id, chat.opts.save_id)
      end
    end

    return original_save_chat(self, chat, ...)
  end

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
        local write_result =
          utils.write_json(self.index_path, utils.remove_functions(index))
        if write_result.ok then
          compact_acp_session_index(self, chat_data.acp_session_id)
        end
        return write_result
      end
    end

    return result
  end

  local original_get_chats = Storage.get_chats
  Storage.get_chats = function(self, filter_fn, ...)
    compact_acp_session_index(self)
    local chats = original_get_chats(self, filter_fn, ...)
    local enriched = false
    for save_id, meta in pairs(chats or {}) do
      if type(meta) == 'table' and not meta.acp_session_id then
        local chat_data = self:load_chat(save_id)
        if chat_data and chat_data.acp_session_id then
          meta.acp_session_id = chat_data.acp_session_id
          enriched = true
        end
      end
    end

    if enriched then
      local index, utils = read_index(self)
      if index and utils then
        for save_id, meta in pairs(chats or {}) do
          if
            type(meta) == 'table'
            and type(meta.acp_session_id) == 'string'
            and meta.acp_session_id ~= ''
          then
            index[save_id] = index[save_id] or {}
            index[save_id].acp_session_id = meta.acp_session_id
          end
        end

        if
          utils.write_json(self.index_path, utils.remove_functions(index)).ok
        then
          compact_acp_session_index(self)
          chats = original_get_chats(self, filter_fn, ...)
        end
      end
    end

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

  if not UI._lpke_acp_open_session then
    UI._lpke_acp_open_session = true

    local original_handle_on_select = UI._handle_on_select
    UI._handle_on_select = function(self, save_id, ...)
      local ok_chat_fns, chat_fns =
        pcall(require, 'lpke.plugins.ai.helpers.chat_functions')
      local restore_context = ok_chat_fns and chat_fns.take_restore_context()
        or nil
      local chat_data = self.storage and self.storage:load_chat(save_id)
      local session_id = chat_data and chat_data.acp_session_id
      local open_chat_for_session = find_open_chat_by_session_id(session_id)
      if open_chat_for_session and open_chat(open_chat_for_session) then
        if ok_chat_fns then
          chat_fns.after_restore(open_chat_for_session, restore_context)
        end
        vim.notify('ACP session already open', vim.log.levels.INFO, {
          title = 'CodeCompanion',
        })
        return
      end

      self._lpke_restore_context = restore_context
      local existing_chat = find_open_chat_by_save_id(save_id)
      local result = original_handle_on_select(self, save_id, ...)
      local restore_applied = false
      if ok_chat_fns and existing_chat then
        chat_fns.after_restore(existing_chat, restore_context)
        restore_applied = true
      end
      if not existing_chat then
        local restored_chat = find_open_chat_by_save_id(save_id)
        if restored_chat then
          chat_fns.after_restore(restored_chat, restore_context)
          restore_applied = true
        end
      end
      if restore_applied then
        self._lpke_restore_context = nil
      end
      return result
    end
  end

  if not UI._lpke_restore_open_saved_chats then
    UI._lpke_restore_open_saved_chats = true

    local original_open_saved_chats = UI.open_saved_chats
    UI.open_saved_chats = function(self, ...)
      local ok_chat_fns, chat_fns =
        pcall(require, 'lpke.plugins.ai.helpers.chat_functions')
      if ok_chat_fns then
        chat_fns.capture_restore_context()
      end
      return original_open_saved_chats(self, ...)
    end
  end

  if not UI._lpke_acp_create_chat then
    UI._lpke_acp_create_chat = true

    local original_create_chat = UI.create_chat
    UI.create_chat = function(self, chat_data, ...)
      local chat = original_create_chat(self, chat_data, ...)
      if chat and chat_data then
        chat.opts = chat.opts or {}
        if chat_data.cwd then
          chat.cwd = chat_data.cwd
          chat.opts.cwd = chat_data.cwd
        end
        if chat_data.project_root then
          chat.project_root = chat_data.project_root
          chat.opts.project_root = chat_data.project_root
        end
        if chat_data.acp_session_id then
          chat.acp_session_id = chat_data.acp_session_id
          chat.opts.acp_session_id = chat_data.acp_session_id
        end
      end
      local ok_chat_fns, chat_fns =
        pcall(require, 'lpke.plugins.ai.helpers.chat_functions')
      if ok_chat_fns then
        chat_fns.after_restore(chat, self._lpke_restore_context)
      end
      self._lpke_restore_context = nil
      return chat
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
