local M = {}
local api = vim.api
local model_swap = require('lpke.plugins.ai.helpers.model_swap')

local function notify(chat, message)
  vim.schedule(function()
    -- Keep notifications in :messages without a hit-enter prompt.
    local messagesopt = vim.o.messagesopt
    local history = messagesopt:match('history:%d+') or 'history:500'
    vim.o.messagesopt = 'wait:0,' .. history
    local ok, err = pcall(
      vim.notify,
      ('AiContinue %s [chat %d]: %s'):format(
        os.date('%H:%M:%S'),
        chat.bufnr,
        message
      ),
      vim.log.levels.INFO,
      { title = 'CodeCompanion' }
    )
    vim.o.messagesopt = messagesopt
    if not ok then
      error(err)
    end
  end)
end

local function capacity_ending(content)
  if type(content) ~= 'string' then
    return false
  end

  local normalized = content:lower():gsub('%p', ' '):gsub('%s+', ' ')
  normalized = vim.trim(normalized)
  for _, subject in ipairs({ 'selected model', 'the selected model' }) do
    for _, condition in ipairs({ 'is at capacity', 'is currently at capacity' }) do
      for _, action in ipairs({ 'try a different model', 'try another model' }) do
        local ending = subject .. ' ' .. condition .. ' please ' .. action
        if
          normalized == ending
          or normalized:sub(-#ending - 1) == ' ' .. ending
        then
          return true
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

  -- The prompt parser strips blockquotes as context, so inspect the raw draft.
  local draft = table.concat(
    api.nvim_buf_get_lines(chat.bufnr, chat.header_line, -1, false),
    '\n'
  )
  return vim.trim(draft) == ''
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
  chat._lpke_auto_continue_response = response
  queue(chat, response)
end

function M.enable(chat)
  if not chat or not model_swap.is_codex_adapter(chat.adapter) then
    vim.notify('AiContinue requires a Codex ACP chat', vim.log.levels.WARN)
    return
  end
  if chat._lpke_auto_continue then
    notify(chat, 'already enabled')
    return
  end

  local state = {}
  chat._lpke_auto_continue = state
  chat:add_callback('on_submitted', function()
    cancel(state)
    state.cancelled = false
    chat._lpke_auto_continue_response = nil
  end)
  chat:add_callback('on_cancelled', function()
    state.cancelled = true
    cancel(state)
  end)
  chat:add_callback('on_closed', function()
    state.cancelled = true
    cancel(state)
  end)
  notify(chat, 'enabled for this chat')
  if chat._lpke_auto_continue_response then
    queue(chat, chat._lpke_auto_continue_response)
  end
end

function M.setup()
  require('lpke.core.helpers').command_set({
    '0',
    'AiContinue',
    function()
      M.enable(require('codecompanion').buf_get_chat(0))
    end,
    { desc = 'Retry Codex capacity endings with continue after 30 seconds' },
  })

  local Handler = require('codecompanion.interactions.chat.acp.handler')
  if Handler._lpke_auto_continue then
    return
  end
  Handler._lpke_auto_continue = true

  local original_complete = Handler.handle_complete
  Handler.handle_complete = function(self, ...)
    -- ACP output also contains tool text. Only match when assistant text was last.
    local content = self.chat.builder.state.last_type
          == self.chat.MESSAGE_TYPES.LLM_MESSAGE
        and table.concat(self.output, '')
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
