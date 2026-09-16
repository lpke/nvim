local M = {}
local pending = {}
local patched = false
local storage

local function history()
  return require('codecompanion').extensions.history
end

local function chats()
  return require('codecompanion').buf_get_chat() or {}
end

local function session_id(chat)
  return (chat.acp_connection and chat.acp_connection.session_id)
    or chat.acp_session_id
    or (chat.opts and chat.opts.acp_session_id)
end

local function clean(title)
  return type(title) == 'string' and vim.trim(title:gsub('^✨%s*', '')) or nil
end

local function valid(title)
  title = clean(title)
  return title
    and title ~= ''
    and title ~= 'Deciding title...'
    and title ~= 'Refreshing title...'
    and title ~= 'CodeCompanion'
    and not title:match('^%[CodeCompanion%]%s')
end

local function settled(title, state)
  title = clean(title)
  return title ~= nil
    and title ~= ''
    and (
      (state and (state.status == 'pending' or state.status == 'done'))
      or valid(title)
    )
end

local function buffer_title(bufnr, title)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  for attempt = 0, 10 do
    local suffix = attempt == 0 and '' or (' (' .. attempt .. ')')
    if pcall(vim.api.nvim_buf_set_name, bufnr, title .. suffix) then
      return
    end
  end
end

local function apply(chat, title, state)
  title = clean(title)
  chat.opts = chat.opts or {}
  chat.opts.title = title
  chat.opts.lpke_title = state and vim.deepcopy(state) or { status = 'done' }
  chat._lpke_history_title_locked = title
  chat._lpke_title_display = title
  chat._lpke_history_title_applying = true
  if type(chat.set_title) == 'function' then
    chat:set_title(title)
  else
    chat.title = title
    if chat.ui then
      chat.ui.title = title
    end
  end
  chat._lpke_history_title_applying = nil
  buffer_title(chat.bufnr, title)
end

local function saved_chat(chat, store)
  local extension = history()
  if not store and not extension then
    return
  end
  local load = function(id)
    if store then
      return store:load_chat(id)
    end
    return extension.load_chat(id)
  end
  local saved = chat.opts.save_id and load(chat.opts.save_id)
  if saved and settled(saved.title, saved.lpke_title) then
    return saved
  end
  local id = session_id(chat)
  if not id then
    return saved
  end
  local newest
  for save_id, meta in
    pairs(store and store:get_chats() or extension.get_chats())
  do
    if
      meta.acp_session_id == id
      and (not newest or meta.updated_at > newest.updated_at)
    then
      local candidate = load(save_id)
      if candidate and settled(candidate.title, candidate.lpke_title) then
        newest = candidate
      end
    end
  end
  return newest or saved
end

function M.restore(chat, store)
  if type(chat) ~= 'table' then
    return false
  end
  chat.opts = chat.opts or {}
  local saved = saved_chat(chat, store)
  if saved and settled(saved.title, saved.lpke_title) then
    chat.opts.save_id = saved.save_id
    local state = saved.lpke_title
    -- An interrupted attempt keeps its saved fallback. Never rerun on resume.
    if state and state.status == 'pending' and not pending[state.id] then
      state = { status = 'done', source = 'fallback' }
    end
    apply(chat, saved.title, state)
    return true
  end
  local title = chat.opts.title or chat._lpke_history_title_locked
  if settled(title, chat.opts.lpke_title) then
    apply(chat, title, chat.opts.lpke_title)
    return true
  end
  return false
end

local function visible_prompt(messages)
  for _, msg in ipairs(messages or {}) do
    local opts, meta = msg.opts or {}, msg._meta or {}
    if
      msg.role == 'user'
      and opts.visible ~= false
      and not msg.context
      and not (opts.tag or opts.reference or opts.context_id)
      and not (meta.tag or meta.reference or meta.context_id)
      and type(msg.content) == 'string'
      and vim.trim(msg.content) ~= ''
    then
      return msg.content
    end
  end
end

local function first_prompt(chat)
  -- Saved messages may already include decorators or expanded references.
  -- Only a draft captured before submission is safe to send to the title model.
  return chat._lpke_first_typed_prompt
end

local function fallback(prompt)
  local words = {}
  for word in prompt:gmatch('%S+') do
    table.insert(words, word)
    if #words == 10 then
      break
    end
  end
  return vim.fn.strcharpart(table.concat(words, ' '), 0, 120)
end

local function notify_changed(save_id, title)
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'LpkeCodeCompanionTitleChanged',
    data = { save_id = save_id, title = title },
  })
end

local function write_title(store, saved, title, state)
  saved.title, saved.lpke_title, saved.updated_at = title, state, os.time()
  if
    not store:_save_chat_to_file(saved).ok
    or not store:_update_index_entry(saved).ok
  then
    return false
  end
  for _, item in ipairs(chats()) do
    local chat = item.chat
    if chat.opts.save_id == saved.save_id then
      apply(chat, title, state)
    end
  end
  local utils = require('codecompanion._extensions.history.utils')
  local path = store.base_path .. '/summaries_index.json'
  local result = utils.read_json(path)
  local changed = false
  for _, summary in pairs(result.ok and result.data or {}) do
    if summary.chat_id == saved.save_id and summary.chat_title ~= title then
      summary.chat_title, changed = title, true
    end
  end
  if changed and utils.write_json(path, result.data).ok then
    store:_invalidate_summaries_cache()
  end
  notify_changed(saved.save_id, title)
  return true
end

function M.generate(generator, chat, callback)
  if M.restore(chat) then
    return callback(chat.opts.title)
  end
  local prompt = first_prompt(chat)
  if not generator.opts.auto_generate_title or not prompt then
    return
  end

  local id = ('%d:%s:%d'):format(
    vim.uv.os_getpid(),
    vim.uv.hrtime(),
    chat.bufnr
  )
  local entry = {}
  pending[id] = entry
  local default_title = fallback(prompt)
  apply(chat, default_title, { status = 'pending', id = id })
  -- Commit a fallback and the attempt ID before starting a process. This also
  -- makes an unfinished request durable without ever requiring a second run.
  history().save_chat(chat)
  local save_id = chat.opts.save_id
  local store = storage
  local saved = history().load_chat(save_id)
  if not saved or not saved.lpke_title or saved.lpke_title.id ~= id then
    pending[id] = nil
    apply(chat, default_title, { status = 'done', source = 'fallback' })
    return callback(default_title)
  end
  notify_changed(save_id, default_title)

  entry.cancel = require('lpke.plugins.ai.helpers.title_request').request(
    prompt,
    function(title)
      if pending[id] ~= entry then
        return
      end
      pending[id] = nil
      saved = store:load_chat(save_id)
      -- Deletion or any rename invalidates the attempt, even a rename to the
      -- identical fallback text. Never overwrite newer messages or revive a chat.
      if not saved or not saved.lpke_title or saved.lpke_title.id ~= id then
        return
      end
      -- Helpers outside this process may only change the title field.
      if saved.title ~= default_title then
        write_title(
          store,
          saved,
          saved.title,
          { status = 'done', source = 'manual' }
        )
        return
      end
      local generated = valid(title)
      title = generated and clean(title) or default_title
      write_title(store, saved, title, {
        status = 'done',
        source = generated and 'generated' or 'fallback',
      })
    end
  )
end

function M.setup()
  if patched then
    return
  end
  patched = true
  local Chat = require('codecompanion.interactions.chat')
  local Storage = require('codecompanion._extensions.history.storage')
  local UI = require('codecompanion._extensions.history.ui')
  local Generator = require('codecompanion._extensions.history.title_generator')

  Generator.should_generate = function(self, chat)
    return self.opts.auto_generate_title
      and not M.restore(chat)
      and first_prompt(chat) ~= nil,
      false
  end
  Generator.generate = M.generate

  -- Capture the actual draft before context expansion and prompt decorators.
  local submit = Chat.submit
  Chat.submit = function(self, opts)
    if
      not self.current_request
      and not (opts and (opts.auto_submit or opts.regenerate))
      and not M.restore(self)
      and not visible_prompt(self.messages)
    then
      local draft = require('codecompanion.interactions.chat.parser').messages(
        self,
        self.header_line
      )
      self._lpke_first_typed_prompt = draft and draft.content or nil
    end
    return submit(self, opts)
  end

  local set_title = Chat.set_title
  Chat.set_title = function(self, title)
    if
      not self._lpke_history_title_applying and self._lpke_history_title_locked
    then
      title = self._lpke_history_title_locked
    end
    return set_title(self, title)
  end

  local save = Storage.save_chat
  Storage.save_chat = function(self, chat, ...)
    storage = self
    chat = chat or require('codecompanion').last_chat()
    if chat then
      M.restore(chat, self)
    end
    return save(self, chat, ...)
  end
  local save_file = Storage._save_chat_to_file
  Storage._save_chat_to_file = function(self, data, ...)
    if not data.lpke_title then
      for _, item in ipairs(chats()) do
        if item.chat.opts.save_id == data.save_id then
          data.lpke_title = item.chat.opts.lpke_title
          break
        end
      end
    end
    return save_file(self, data, ...)
  end

  Storage.rename_chat = function(self, save_id, title)
    local saved = self:load_chat(save_id)
    title = clean(title)
    if not saved or not title or title == '' then
      return false
    end
    local request = saved.lpke_title and pending[saved.lpke_title.id]
    local ok =
      write_title(self, saved, title, { status = 'done', source = 'manual' })
    if ok and request and request.cancel then
      request.cancel()
    end
    return ok
  end

  local update_title = UI.update_chat_title
  UI.update_chat_title = function(self, chat, suffix, force)
    M.restore(chat)
    if chat.opts.title then
      chat._lpke_title_display = suffix
          and (force and suffix or (chat.opts.title .. ' ' .. suffix))
        or chat.opts.title
    end
    return update_title(self, chat, suffix, force)
  end
  local group =
    vim.api.nvim_create_augroup('LpkeCodeCompanionTitles', { clear = true })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'CodeCompanionHistoryTitleSet',
    callback = function(args)
      local data = args.data or {}
      local chat = data.bufnr and Chat.buf_get_chat(data.bufnr)
      local title = clean(data.title)
      local locked = chat and chat._lpke_history_title_locked
      if locked then
        chat.opts.title = locked
        title = chat._lpke_title_display or locked
      end
      if title then
        buffer_title(data.bufnr, title)
      end
    end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = {
      'CodeCompanionChatCreated',
      'CodeCompanionACPChatRestored',
      'CodeCompanionACPSessionPost',
      'CodeCompanionRequestFinished',
    },
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if args.match == 'CodeCompanionChatCreated' and bufnr then
        local chat = Chat.buf_get_chat(bufnr)
        if chat and not chat.opts.save_id then
          -- Upstream uses seconds alone, so quick new chats can share history.
          -- Assign before its scheduled ChatCreated handler runs.
          chat.opts.save_id = ('%d-%d-%s'):format(
            os.time(),
            vim.uv.os_getpid(),
            vim.uv.hrtime()
          )
        end
      end
      vim.schedule(function()
        if bufnr then
          M.restore(Chat.buf_get_chat(bufnr))
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      for _, entry in pairs(vim.tbl_extend('force', {}, pending)) do
        if entry.cancel then
          entry.cancel()
        end
      end
    end,
  })
end

return M
