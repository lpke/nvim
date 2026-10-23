-- nvim --headless -u NONE -l tests/codecompanion_send_in.lua
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
local timers, notices = {}, {}
local original_defer = vim.defer_fn
vim.notify = function(message)
  assert(
    not vim.o.messagesopt:find('hit-enter', 1, true),
    'Blocking notification'
  )
  notices[#notices + 1] = message
end
vim.defer_fn = function(callback, delay)
  if delay < 1000 then
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
require('lpke.plugins.ai.helpers.send_in').setup()
require('lpke.plugins.ai.helpers.send_in').setup()
require('codecompanion.interactions.chat.helpers').create_acp_connection = function(
  chat,
  callback
)
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
  if callback then
    callback()
  end
end
local Chat = require('codecompanion.interactions.chat')
local function flush()
  vim.wait(15, function()
    return false
  end)
end
local function new_chat(adapter, prompt)
  local chat = assert(Chat.new({
    adapter = adapter or 'codex',
    buffer_context = {
      bufnr = api.nvim_get_current_buf(),
      filetype = 'lua',
      filename = 'fixture.lua',
      lines = {},
    },
  }))
  local function sent(self, payload)
    self.last_payload = payload
    self.current_request = { cancel = function() end }
  end
  chat._submit_acp, chat._submit_http = sent, sent
  api.nvim_set_current_buf(chat.bufnr)
  flush()
  if prompt ~= false then
    chat:add_buf_message({
      role = 'user',
      content = prompt or 'Send this exact draft',
    })
  end
  return chat
end
local function command(text)
  vim.cmd('SendIn ' .. text)
  flush()
end
local function expire(timer)
  timer:close()
  timer.callback()
  flush()
end
local function latest()
  return timers[#timers]
end
local function notice(text)
  flush()
  return table.concat(notices, '\n'):find(text, 1, true)
end

local chat = new_chat()
command('1m')
local first = latest()
assert(first.delay == 60000, 'Minute duration incorrect')
command('list')
assert(notice('#1 [chat ' .. chat.bufnr .. ']'), 'List omitted current timer')
local other = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(other)
expire(first)
assert(
  api.nvim_get_current_buf() == other,
  'Background send stole buffer focus'
)
assert(chat.current_request, 'Background draft was not sent')
local message = chat.messages[#chat.messages]
assert(message.content == 'Send this exact draft', 'Scheduled prompt changed')
assert(notice('sent at'), 'Missing sent notification')
local count = #timers
command('2h')
assert(#timers == count, 'Non-chat buffer accepted timer')
assert(notice('only in CodeCompanion'), 'Missing non-chat error')

local a, b = new_chat('codex', 'A'), new_chat('copilot', 'B')
command('2h')
assert(latest().delay == 7200000, 'Hour duration incorrect')
local b_timer = latest()
api.nvim_set_current_buf(a.bufnr)
command('1h30m')
assert(latest().delay == 5400000, 'Compound duration incorrect')
local a_timer = latest()
command('list all')
assert(notice('[chat ' .. b.bufnr .. ']'), 'List all omitted other chat')
command('cancel 2')
assert(b_timer.closed, 'Cancel by ID did not cancel other chat')
command('cancel')
assert(a_timer.closed, 'Cancel current failed')
expire(a_timer)
expire(b_timer)
assert(not a.current_request and not b.current_request, 'Cancelled sends ran')
command('30s')
local replaced = latest()
command('1d')
assert(replaced.closed and latest().delay == 86400000, 'Replacement failed')
api.nvim_set_current_buf(b.bufnr)
command('1m')
local all = latest()
command('cancel all')
assert(all.closed, 'Cancel all failed')
command('list all')
assert(
  notices[#notices] == 'No scheduled sends',
  'Cancelled jobs remained queued'
)

for _, invalid in ipairs({
  '0m',
  '-1m',
  '1.5h',
  '1x',
  '25d',
  '2hgarbage',
  'cancel nope',
  'list extra',
}) do
  count = #timers
  command(invalid)
  assert(#timers == count, 'Invalid command scheduled a send: ' .. invalid)
end
local empty = new_chat(nil, false)
count = #timers
command('1m')
assert(#timers == count, 'Empty draft accepted')

local interventions = {
  edit = function(target)
    api.nvim_buf_set_lines(target.bufnr, -1, -1, false, { 'changed' })
  end,
  quote = function(target)
    api.nvim_buf_set_lines(target.bufnr, -1, -1, false, { '> changed' })
  end,
  revert = function(target)
    api.nvim_buf_set_lines(target.bufnr, -1, -1, false, { 'changed' })
    api.nvim_buf_set_lines(target.bufnr, -2, -1, false, {})
  end,
  manual = function(target)
    target:submit()
  end,
  stop = function(target)
    target:stop()
  end,
  close = function(target)
    target:close()
  end,
  clear = function(target)
    target:clear()
  end,
  wipe = function(target)
    api.nvim_buf_delete(target.bufnr, { force = true })
  end,
  busy = function(target)
    target.current_request = {}
  end,
  session = function(target)
    target.acp_connection.session_id = 'new-session'
  end,
  cycle = function(target)
    target.cycle = target.cycle + 1
  end,
  adapter = function(target)
    target:change_adapter('ollama')
  end,
  readonly = function(target)
    vim.bo[target.bufnr].modifiable = false
  end,
}
for label, intervene in pairs(interventions) do
  local target = new_chat()
  command('1m')
  local timer = latest()
  intervene(target)
  local previous = target.last_payload
  -- Expire before deferred edit callbacks to exercise the final safety checks too.
  expire(timer)
  assert(target.last_payload == previous, label .. ' failed to prevent sending')
end
local http = new_chat('ollama', 'HTTP draft')
command('1m')
expire(latest())
assert(
  http.current_request and http.messages[#http.messages].content == 'HTTP draft',
  'HTTP send failed'
)

local veto = new_chat()
veto:add_callback('on_before_submit', function()
  return false
end)
command('1m')
expire(latest())
assert(not veto.current_request, 'Submission bypassed CodeCompanion veto')
assert(notice('was not submitted; draft retained'), 'Veto reported as sent')

local contextual = new_chat(nil, false)
contextual.context_items = {
  { id = '<rules>AGENTS.md</rules>', opts = { visible = true } },
}
contextual.context:render()
contextual:add_buf_message({ role = 'user', content = 'Contextual prompt' })
command('1m')
expire(latest())
assert(
  contextual.messages[#contextual.messages].content == 'Contextual prompt',
  'Context changed scheduled prompt'
)

-- Exercise a real timer with another window focused and no model transport.
local real = new_chat()
vim.defer_fn = original_defer
command('1s')
local focused = api.nvim_open_win(other, true, { split = 'right' })
assert(
  vim.wait(1500, function()
    return real.current_request ~= nil
  end),
  'Real timer did not submit in background'
)
assert(
  api.nvim_get_current_win() == focused and api.nvim_get_current_buf() == other,
  'Real timer changed the focused window'
)
print(
  'PASS: scheduled background sends, units, list/cancel/replacement, exact drafts, ACP/HTTP and intervention guards'
)
