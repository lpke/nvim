local M = {}
local api = vim.api
local model_swap = require('lpke.plugins.ai.helpers.model_swap')
local draft = require('lpke.plugins.ai.helpers.chat_draft')
local chat_notify = require('lpke.plugins.ai.helpers.chat_notify')

local function notify(chat, message)
  chat_notify(
    ('Codex retry %s [chat %d]: %s'):format(
      os.date('%H:%M:%S'),
      chat.bufnr,
      message
    )
  )
end

local function capacity_ending(content)
  if type(content) ~= 'string' then
    return false
  end

  if content:find('```', 1, true) or content:find('~~~', 1, true) then
    return false
  end
  -- The error must start a line, rather than end a quoted example or sentence.
  local candidates = {}
  local start = math.max(1, #content - 511)
  if start > 1 and content:sub(start - 1, start - 1) ~= '\n' then
    local newline = content:find('\n', start, true)
    if not newline then
      return false
    end
    start = newline + 1
  end
  content = content:sub(start)
  for offset in ('\n' .. content):gmatch('()\n') do
    local tail = vim.trim(content:sub(offset))
    if tail:match('^%a') then
      candidates[#candidates + 1] =
        vim.trim(tail:lower():gsub('%p', ' '):gsub('%s+', ' '))
    end
  end
  for _, subject in ipairs({ 'selected model', 'the selected model' }) do
    for _, condition in ipairs({ 'is at capacity', 'is currently at capacity' }) do
      for _, action in ipairs({ 'try a different model', 'try another model' }) do
        local ending = subject .. ' ' .. condition .. ' please ' .. action
        for _, normalized in ipairs(candidates) do
          if normalized == ending then
            return true
          end
        end
      end
    end
  end
  return false
end

local function cancel(state)
  state.pending = nil
  if state.timer and not state.timer:is_closing() then
    state.timer:stop()
    state.timer:close()
  end
  state.timer = nil
end

local function session_id(chat)
  return chat.acp_connection and chat.acp_connection.session_id
    or chat.acp_session_id
end

local function can_continue(chat, response)
  if
    not model_swap.is_codex_adapter(chat.adapter)
    or not api.nvim_buf_is_valid(chat.bufnr)
    or require('codecompanion').buf_get_chat(chat.bufnr) ~= chat
    or chat.current_request
    or (chat.status and chat.status ~= '')
    or not vim.bo[chat.bufnr].modifiable
    or chat._last_role ~= require('codecompanion.config').constants.USER_ROLE
    or chat.cycle ~= response.cycle
    or chat.messages[#chat.messages] ~= response.message
    or session_id(chat) ~= response.session_id
    or not capacity_ending(response.content)
  then
    return false
  end

  return draft.empty(chat)
end

local function queue(chat, response)
  local state = chat._lpke_auto_continue
  if not state or state.cancelled or not can_continue(chat, response) then
    return
  end
  if state.pending == response then
    return
  end

  cancel(state)
  state.pending = response
  notify(chat, 'capacity reached; waiting 30s')
  state.timer = vim.defer_fn(function()
    if state.pending ~= response then
      return
    end
    state.timer = nil
    state.pending = nil
    if not can_continue(chat, response) then
      notify(chat, 'retry cancelled; chat changed or busy')
      return
    end

    local ok, err = pcall(api.nvim_buf_call, chat.bufnr, function()
      chat:add_buf_message({
        role = require('codecompanion.config').constants.USER_ROLE,
        content = 'continue',
      })
      chat:submit()
    end)
    if not ok then
      notify(chat, 'retry failed: ' .. tostring(err):gsub('%s+', ' '))
    elseif chat.current_request then
      notify(chat, 'sent continue')
    else
      notify(chat, 'continue was not submitted')
    end
  end, 30000)
end

local function record_response(chat, content)
  if not model_swap.is_codex_adapter(chat.adapter) then
    return
  end
  local response = {
    content = content,
    message = chat.messages[#chat.messages],
    cycle = chat.cycle,
    session_id = session_id(chat),
  }
  queue(chat, response)
end

local function attach(chat)
  if
    not chat
    or not model_swap.is_codex_adapter(chat.adapter)
    or chat._lpke_auto_continue
  then
    return
  end

  local state = {}
  chat._lpke_auto_continue = state
  chat:add_callback('on_submitted', function()
    cancel(state)
    state.cancelled = false
  end)
  chat:add_callback('on_cancelled', function()
    state.cancelled = true
    cancel(state)
  end)
  chat:add_callback('on_closed', function()
    state.cancelled = true
    cancel(state)
  end)
end

function M.setup()
  api.nvim_create_autocmd('User', {
    group = api.nvim_create_augroup('LpkeCodeCompanionAutoContinue', {
      clear = true,
    }),
    pattern = { 'CodeCompanionChatCreated', 'CodeCompanionChatAdapter' },
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if bufnr then
        attach(require('codecompanion').buf_get_chat(bufnr))
      end
    end,
  })
  for _, entry in ipairs(require('codecompanion').buf_get_chat()) do
    attach(entry.chat)
  end

  local Handler = require('codecompanion.interactions.chat.acp.handler')
  if Handler._lpke_auto_continue then
    return
  end
  Handler._lpke_auto_continue = true

  local original_chunk = Handler.handle_message_chunk
  Handler.handle_message_chunk = function(self, content, ...)
    if self.chat.builder.state.block_type ~= 'llm' then
      self._lpke_assistant_chunks = {}
    end
    self._lpke_assistant_chunks = self._lpke_assistant_chunks or {}
    table.insert(self._lpke_assistant_chunks, content)
    return original_chunk(self, content, ...)
  end

  local original_complete = Handler.handle_complete
  Handler.handle_complete = function(self, ...)
    -- ACP output also contains tool text. Only match when assistant text was last.
    local content = self.chat.builder.state.block_type == 'llm'
        and table.concat(self._lpke_assistant_chunks or {}, '')
      or nil
    local result = original_complete(self, ...)
    record_response(self.chat, content)
    return result
  end

  local original_error = Handler.handle_error
  Handler.handle_error = function(self, err, ...)
    local result = original_error(self, err, ...)
    record_response(self.chat, err)
    return result
  end
end

return M
