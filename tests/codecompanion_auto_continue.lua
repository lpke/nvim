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
  if not message:match('^Codex retry ') then
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
local Chat = require('codecompanion.interactions.chat')
local Handler = require('codecompanion.interactions.chat.acp.handler')
local adapters = require('codecompanion.adapters')
local capacity = 'Selected model is at capacity. Please try a different model.'

-- New and restored ACP chats use a fake connection without starting an agent.
require('codecompanion.interactions.chat.helpers').create_acp_connection = function(
  chat,
  callback
)
  chat.acp_connection = {
    session_id = chat.acp_session_id or 'fixture-' .. chat.bufnr,
    get_models = function()
      return {}
    end,
    get_config_options = function()
      return {}
    end,
    disconnect = function() end,
  }
  if callback then
    callback()
  end
end

local function flush()
  vim.wait(20, function()
    return false
  end)
end

local function new_chat(adapter, opts)
  opts = opts or {}
  opts.adapter = adapter or 'codex'
  opts.buffer_context = {
    bufnr = api.nvim_get_current_buf(),
    filetype = 'lua',
    filename = 'fixture.lua',
    lines = {},
  }
  local chat = assert(Chat.new(opts))
  -- Use the real submit, handler, parser and ACP formatter with no agent process.
  chat._submit_acp = function(self, payload)
    self.last_prompt =
      self.adapter.handlers.form_messages(self.adapter, payload.messages, {})
    self.current_request = { cancel = function() end }
  end
  api.nvim_set_current_buf(chat.bufnr)
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
submit(chat)
auto_continue.setup()
local state = chat._lpke_auto_continue
assert(state, 'An already running Codex chat was not attached')
assert(vim.fn.exists(':AiContinue') == 0, 'Activation command still exists')
auto_continue.setup()
assert(chat._lpke_auto_continue == state, 'Repeated setup duplicated state')
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

for _, target in ipairs({
  new_chat(),
  new_chat(nil, { acp_session_id = 'restored-fixture' }),
}) do
  assert(
    target._lpke_auto_continue,
    'A new or restored Codex chat was not attached'
  )
  submit(target)
  count = #timers
  finish(target, capacity)
  assert(#timers == count + 1, 'A new or restored Codex chat did not retry')
  expire(timers[#timers])
  assert(target.current_request, 'Automatic retry was not submitted')
  finish(target, 'Recovered')
end

local switched = new_chat('ollama')
assert(not switched._lpke_auto_continue, 'HTTP chat was attached')
switched:change_adapter('codex')
flush()
assert(
  switched._lpke_auto_continue,
  'Switching to Codex did not attach retries'
)
submit(switched)
count = #timers
finish(switched, capacity)
assert(#timers == count + 1, 'Switching to Codex did not enable retries')
expire(timers[#timers])
finish(switched, 'Recovered')

local non_codex = new_chat('claude_code')
assert(
  not non_codex._lpke_auto_continue,
  'A different ACP adapter was attached'
)
count = #timers
finish(non_codex, capacity)
assert(#timers == count, 'A different ACP adapter retried')

for _, content in ipairs({
  capacity .. '\nI will keep working.',
  'You said: ' .. capacity .. '\nThat was just an example.',
  'Selected model is available. Please try a different model.',
  'Selected model is at capacity. Please try again later.',
  'You said: ' .. capacity,
  '> ' .. capacity,
  '```txt\n' .. capacity .. '\n```',
  '~~~txt\n' .. capacity .. '\n~~~',
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

-- Real failures follow tool/compaction summaries and retain automatic context.
local contextual = new_chat()
contextual.context_items = {
  { id = '<rules>AGENTS.md</rules>', opts = { visible = true } },
  { id = '<rules>/tmp/rules.md</rules>', opts = { visible = true } },
  { id = '<file>hidden</file>', opts = { visible = false } },
}
submit(contextual)
handler = Handler.new(contextual)
handler:handle_message_chunk('Work in progress.')
handler:process_tool_call({
  toolCallId = 'compaction',
  kind = 'think',
  title = 'Compact conversation',
  status = 'completed',
})
handler:handle_message_chunk('Selected model is at ')
handler:handle_message_chunk('capacity. Please try a different model.')
count = #timers
handler:handle_complete()
flush()
assert(#timers == count + 1, 'Tool summary or automatic context blocked retry')
expire(timers[#timers])
assert(contextual.current_request, 'Contextual retry was not submitted')
assert(
  vim.deep_equal(
    contextual.last_prompt,
    { { type = 'text', text = 'continue' } }
  ),
  'Automatic context leaked into retry prompt'
)
finish(contextual, 'Done')

submit(contextual)
finish(contextual, capacity)
local context_timer = timers[#timers]
api.nvim_buf_set_lines(contextual.bufnr, -1, -1, false, { '> Keep this quote' })
expire(context_timer)
assert(not contextual.current_request, 'Context masked a user-authored quote')

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
  'PASS: automatic retries for existing/new/restored/switched Codex chats, capacity endings, exact prompts, errors, interventions and notifications'
)
