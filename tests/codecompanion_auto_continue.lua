-- nvim --headless -u NONE -l tests/codecompanion_auto_continue.lua
table.unpack = table.unpack or unpack
vim.opt.rtp:prepend(vim.fn.getcwd())
for _, plugin in ipairs({
  'codecompanion.nvim',
  'plenary.nvim',
  'nvim-treesitter',
}) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end
require('lpke.core.globals')

local api = vim.api
local notifications, timers = {}, {}
local original_notify, original_defer = vim.notify, vim.defer_fn
vim.notify = function(message)
  if not message:match('^AiContinue ') then
    return
  end
  assert(
    not vim.o.messagesopt:find('hit-enter', 1, true),
    'Blocking notification'
  )
  notifications[#notifications + 1] = message
  original_notify(message)
end
vim.defer_fn = function(callback, delay)
  if delay ~= 30000 then
    return original_defer(callback, delay)
  end
  local timer = { callback = callback, delay = delay }
  function timer:is_closing()
    return self.closed or false
  end
  function timer:stop() end
  function timer:close()
    self.closed = true
  end
  timers[#timers + 1] = timer
  return timer
end

require('codecompanion').setup({
  display = {
    chat = {
      start_in_insert_mode = false,
      show_settings = false,
      auto_scroll = false,
    },
  },
  interactions = {
    chat = { adapter = 'ollama', opts = { completion_provider = 'default' } },
  },
})
require('lpke.plugins.ai.helpers.submit_guard').setup()
local auto_continue = require('lpke.plugins.ai.helpers.auto_continue')
auto_continue.setup()
local Chat = require('codecompanion.interactions.chat')
local Handler = require('codecompanion.interactions.chat.acp.handler')
local adapters = require('codecompanion.adapters')
local capacity = 'Selected model is at capacity. Please try a different model.'

local function flush()
  vim.wait(20, function()
    return false
  end)
end

local function new_chat(enable)
  local chat = assert(Chat.new({
    adapter = 'ollama',
    buffer_context = {
      bufnr = api.nvim_get_current_buf(),
      filetype = 'lua',
      filename = 'fixture.lua',
      lines = {},
    },
  }))
  chat.adapter = adapters.resolve('codex')
  chat.acp_connection = {
    session_id = 'fixture-' .. chat.bufnr,
    get_models = function()
      return {}
    end,
    get_config_options = function()
      return {}
    end,
    disconnect = function() end,
  }
  -- Use the real submit, handler, parser and ACP formatter with no agent process.
  chat._submit_acp = function(self, payload)
    self.last_prompt =
      self.adapter.handlers.form_messages(self.adapter, payload.messages, {})
    self.current_request = { cancel = function() end }
  end
  api.nvim_set_current_buf(chat.bufnr)
  if enable ~= false then
    vim.cmd('AiContinue')
  end
  flush()
  return chat
end

local function submit(chat, prompt)
  api.nvim_buf_call(chat.bufnr, function()
    chat:add_buf_message({ role = 'user', content = prompt or 'Do the task' })
    chat:submit()
  end)
end

local function finish(chat, content, opts)
  opts = opts or {}
  local handler = Handler.new(chat)
  api.nvim_buf_call(chat.bufnr, function()
    if opts.error then
      handler:handle_error(content)
    else
      handler:handle_message_chunk(content)
      if opts.tool then
        handler:process_tool_call({
          toolCallId = 'fixture-tool',
          kind = 'read',
          title = 'Read fixture',
          status = 'completed',
          content = {
            { type = 'content', content = { type = 'text', text = capacity } },
          },
        })
      end
      handler:handle_complete()
    end
  end)
  flush()
  return handler
end

local function expire(timer)
  timer:close()
  timer.callback()
  flush()
end

local chat = new_chat()
local state = chat._lpke_auto_continue
vim.cmd('AiContinue')
assert(chat._lpke_auto_continue == state, 'Enabling twice duplicated state')
submit(chat)
local handler = Handler.new(chat)
handler:handle_message_chunk(capacity)
assert(#timers == 0, 'Streamed text triggered a retry')
handler:handle_message_chunk('\nStill processing.')
handler:handle_complete()
assert(#timers == 0, 'A mention before the response ending triggered a retry')

submit(chat)
finish(chat, 'Partial progress.\n' .. capacity)
local timer = timers[#timers]
assert(timer and timer.delay == 30000, 'Missing 30-second retry')
local count = #timers
-- Another buffer may be focused when the retry expires.
local other = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(other)
expire(timer)
assert(api.nvim_get_current_buf() == other, 'Retry changed the focused buffer')
assert(chat.current_request, 'Retry was not submitted')
assert(
  vim.deep_equal(chat.last_prompt, { { type = 'text', text = 'continue' } }),
  'Retry prompt was not exactly continue'
)
assert(
  #timers == count,
  'Sending a retry started another timer before completion'
)
finish(
  chat,
  'Selected MODEL is currently at capacity!\n Please   try another model...\n'
)
assert(#timers == count + 1, 'Repeated capacity response did not retry')
expire(timers[#timers])
finish(chat, 'Done')
assert(not state.pending, 'Successful response left a retry queued')

local disabled = new_chat(false)
submit(disabled)
count = #timers
finish(disabled, capacity)
assert(#timers == count, 'An unenabled chat retried')
vim.cmd('AiContinue')
assert(#timers == count + 1, 'Enabling after a capacity ending did not retry')
disabled:dispatch('on_cancelled')

for _, content in ipairs({
  capacity .. '\nI will keep working.',
  'You said: ' .. capacity .. '\nThat was just an example.',
  'Selected model is available. Please try a different model.',
  'Selected model is at capacity. Please try again later.',
}) do
  submit(chat)
  count = #timers
  finish(chat, content)
  assert(
    #timers == count,
    'Unrelated or non-final text triggered a retry: ' .. content
  )
end

-- A final tool result and reasoning text must not masquerade as an answer.
submit(chat)
count = #timers
finish(chat, 'Reading a file.', { tool = true })
assert(#timers == count, 'Tool output triggered a retry')
submit(chat)
handler = Handler.new(chat)
handler:handle_thought_chunk(capacity)
handler:handle_complete()
assert(#timers == count, 'Reasoning triggered a retry')

-- ACP errors appear in the buffer rather than the stored assistant message.
submit(chat)
finish(chat, capacity, { error = true })
assert(#timers == count + 1, 'Final ACP error did not retry')
expire(timers[#timers])
assert(
  vim.deep_equal(chat.last_prompt, { { type = 'text', text = 'continue' } }),
  'Error retry included earlier prompts'
)
finish(chat, 'Recovered')

local interventions = {
  draft = function(target)
    api.nvim_buf_set_lines(target.bufnr, -1, -1, false, { 'Keep my draft' })
  end,
  quote = function(target)
    api.nvim_buf_set_lines(target.bufnr, -1, -1, false, { '> Keep my quote' })
  end,
  submit = function(target)
    submit(target, 'New request')
  end,
  stop = function(target)
    target:stop()
  end,
  busy = function(target)
    target.current_request = {}
  end,
  session = function(target)
    target.acp_connection.session_id = 'different-thread'
  end,
  response = function(target)
    target:add_message({ role = 'llm', content = 'A newer response' })
  end,
  adapter = function(target)
    target.adapter = adapters.resolve('ollama')
  end,
  clear = function(target)
    target:clear()
  end,
  close = function(target)
    target:close()
  end,
}
for label, intervene in pairs(interventions) do
  local target = new_chat()
  submit(target)
  finish(target, capacity)
  local pending = timers[#timers]
  local previous_prompt = target.last_prompt
  intervene(target)
  flush()
  local after_intervention = target.last_prompt
  expire(pending)
  assert(
    target.last_prompt == after_intervention,
    label .. ' did not prevent retry'
  )
  if label == 'draft' then
    assert(
      api.nvim_buf_get_lines(target.bufnr, -2, -1, false)[1] == 'Keep my draft',
      'Draft was changed'
    )
  elseif label == 'submit' then
    assert(
      previous_prompt ~= after_intervention,
      'Manual submission did not run'
    )
  end
end

flush()
assert(
  vim.o.messagesopt:find('hit-enter', 1, true),
  'Notification changed messagesopt'
)
assert(
  table.concat(notifications, '\n'):find('sent continue', 1, true),
  'Missing sent notification'
)
assert(
  vim.fn.execute('messages'):find('sent continue', 1, true),
  'Notification missing from message history'
)
print(
  'PASS: capacity endings, completion, exact prompts, repeated retries, errors, interventions and notifications'
)
