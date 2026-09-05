-- Run from the repo: nvim --headless -u NONE -l tests/codecompanion_ui.lua
table.unpack = table.unpack or unpack
vim.opt.rtp:prepend(vim.fn.getcwd())
for _, plugin in ipairs({
  'codecompanion.nvim',
  'codecompanion-history.nvim',
  'plenary.nvim',
  'nvim-treesitter',
}) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end
require('lpke.core.globals')
require('lpke.core.keymaps')
vim.o.columns, vim.o.lines = 160, 48

local api = vim.api
local function eq(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    (label or 'mismatch')
      .. '\n'
      .. vim.inspect(actual)
      .. '\nexpected '
      .. vim.inspect(expected)
  )
end
local function press(keys)
  api.nvim_feedkeys(
    api.nvim_replace_termcodes(keys, true, false, true),
    'xt',
    false
  )
end
local function key(lhs)
  assert(
    not vim.tbl_isempty(vim.fn.maparg(lhs, 'n', false, true)),
    'Missing mapping: ' .. lhs
  )
  press(lhs)
end
local function lines(buf)
  return api.nvim_buf_get_lines(buf or 0, 0, -1, false)
end
local function contains(buf, value)
  return table.concat(lines(buf), '\n'):find(value, 1, true) ~= nil
end
local function check_hints(buf)
  local namespace = api.nvim_get_namespaces().LpkeChatHints
  local groups = {}
  for _, mark in
    ipairs(api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true }))
  do
    groups[mark[4].hl_group] = true
  end
  assert(
    groups.Comment and groups.DiagnosticInfo,
    'Hints need muted text and accented keys'
  )
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
local Chat = require('codecompanion.interactions.chat')
local history = require('lpke.plugins.ai.helpers.chat_history')
history.setup()
require('lpke.plugins.ai.helpers.folds').setup()
local chat = assert(Chat.new({
  adapter = 'ollama',
  buffer_context = {
    bufnr = vim.api.nvim_get_current_buf(),
    filetype = 'lua',
    filename = 'test.lua',
    lines = {},
  },
}))
local function exchange(index, length)
  chat:add_buf_message({ role = 'user', content = 'Prompt ' .. index })
  local content = string.rep('Response ' .. index .. '\n', length)
  chat:add_message({ role = 'user', content = 'Prompt ' .. index })
  chat:add_message({ role = 'llm', content = content })
  chat:add_buf_message({ role = 'llm', content = content })
end
for index = 1, 30 do
  exchange(index, 180)
end
chat:ready_for_input()
api.nvim_buf_set_lines(chat.bufnr, -1, -1, false, { 'Draft survives' })
local original, messages = lines(chat.bufnr), vim.deepcopy(chat.messages)
api.nvim_win_set_cursor(0, { #original, 0 })
chat.ui.cursor.pos = { #original, 0 }
local parser = require('codecompanion.interactions.chat.parser')
local draft = parser.messages(chat, chat.header_line)
local marks = api.nvim_create_namespace('HistoryRegression')
api.nvim_buf_set_extmark(chat.bufnr, marks, 10, 0, {})
local retained_mark =
  api.nvim_buf_set_extmark(chat.bufnr, marks, #original - 5, 0, {})
chat.ui.folds.fold_summaries[chat.bufnr] =
  { [10] = { content = 'old' }, [#original - 5] = { content = 'retained' } }
local before = vim.uv.hrtime()
history.compact(chat)
local elapsed = (vim.uv.hrtime() - before) / 1e6
local remaining = lines(chat.bufnr)
assert(#remaining >= 300 and #remaining < 650, 'Buffer did not shrink')
eq(chat.messages, messages, 'Model context changed')
eq(parser.messages(chat, chat.header_line), draft, 'Draft parsing changed')
eq(api.nvim_win_get_cursor(0)[1], #remaining, 'Cursor moved off draft')
eq(chat.ui.cursor.pos[1], #remaining, 'Saved cursor was not shifted')
local removed = #original - #remaining
eq(
  api.nvim_buf_get_extmark_by_id(chat.bufnr, marks, retained_mark, {}),
  { #remaining - 5, 0 },
  'Retained mark was not shifted'
)
eq(
  #api.nvim_buf_get_extmarks(chat.bufnr, marks, 0, -1, {}),
  1,
  'Archived mark leaked'
)
eq(
  chat.ui.folds.fold_summaries[chat.bufnr],
  { [#remaining - 5] = { content = 'retained' } },
  'Fold summaries were not shifted'
)
eq(remaining, vim.list_slice(original, removed + 1), 'Retained text changed')
vim.cmd('silent undo')
eq(lines(chat.bufnr), remaining, 'Undo restored archived lines')

history.toggle(chat)
local archive = api.nvim_get_current_buf()
check_hints(archive)
assert(archive ~= chat.bufnr and not vim.bo[archive].modifiable)
assert(api.nvim_buf_line_count(archive) <= 504, 'History page is unbounded')
local newest = lines(archive)[1]
assert(newest:match('Page %d+ of %d+'), 'Missing page indicator')
key('H')
assert(lines(archive)[1] ~= newest, 'H did not go to the previous page')
key('L')
eq(lines(archive)[1], newest, 'L did not go to the next page')
local history_win = api.nvim_get_current_win()
local footer = api.nvim_win_get_config(history_win).footer
assert(
  footer and footer[1][1]:find('Page', 1, true),
  'Missing pinned page indicator'
)
press('2H')
local two_older = lines(archive)[1]
key(']p')
key(']p')
eq(lines(archive)[1], newest, 'Bracket paging did not restore newest page')
key('[p')
key('[p')
eq(lines(archive)[1], two_older, 'Counted paging differs from bracket paging')
while not lines(archive)[1]:find('lines 1-', 1, true) do
  key('[p')
end
local reconstructed = {}
repeat
  vim.list_extend(reconstructed, vim.list_slice(lines(archive), 5))
  local heading = lines(archive)[1]
  key('L')
  if lines(archive)[1] == heading then
    break
  end
until false
eq(
  reconstructed,
  vim.list_slice(original, 1, removed),
  'Archive lost or duplicated text'
)
local input = vim.ui.input
vim.ui.input = function(_, callback)
  callback('^Prompt 2$')
end
key('/')
local match = api.nvim_get_current_line()
eq(match, 'Prompt 2', 'Search did not cross pages')
key('n')
eq(api.nvim_get_current_line(), match, 'Search did not wrap')
key('N')
eq(api.nvim_get_current_line(), match, 'Reverse search did not wrap')
vim.ui.input = input
key('gF')
assert(not api.nvim_buf_is_valid(archive), 'History toggle leaked buffer')
eq(api.nvim_get_current_buf(), chat.bufnr, 'History did not return to chat')

require('codecompanion._extensions.history.log').setup_logging(false)
local storage_dir = vim.fn.tempname()
local storage = require('codecompanion._extensions.history.storage').new({
  dir_to_save = storage_dir,
})
chat.opts.save_id = 'history-regression'
storage:save_chat(chat)
local saved =
  assert(storage:load_chat(chat.opts.save_id), 'Saving trimmed chat failed')
eq(saved.messages, messages, 'Saved history lost archived messages')
vim.fn.delete(storage_dir, 'rf')

local payload
chat._submit_http = function(_, value)
  payload = value
end
chat:submit()
assert(
  payload and #payload.messages >= #messages,
  'Submission lost older context'
)
eq(
  chat.messages[#chat.messages].content,
  'Draft survives',
  'Wrong prompt submitted'
)
chat.current_request = {}
chat:add_buf_message({ role = 'llm', content = string.rep('streaming\n', 800) })
local streaming = lines(chat.bufnr)
history.compact(chat)
eq(lines(chat.bufnr), streaming, 'Compacted a live request')
history.toggle(chat)
key('q')
eq(lines(chat.bufnr), streaming, 'Browsing history changed the live buffer')
chat.current_request = nil
chat.status = 'success'
chat:done({ 'Final answer' })
vim.wait(100, function()
  return false
end)
exchange(31, 50)
chat:ready_for_input()
history.compact(chat)
eq(parser.messages(chat, chat.header_line), nil, 'Ready prompt parsing broke')
chat:clear()
history.toggle(chat)
eq(api.nvim_get_current_buf(), chat.bufnr, 'Clear left an old archive')
chat:close()

-- Reopening saved messages renders a full transcript, then trims it through
-- the normal ChatCreated event. Quoted user headings must stay in their turn.
local restored_messages = vim.deepcopy(saved.messages)
table.insert(restored_messages, { role = 'user', content = '' })
local restored = assert(Chat.new({
  adapter = 'ollama',
  messages = restored_messages,
  buffer_context = { bufnr = api.nvim_get_current_buf(), lines = {} },
}))
assert(
  vim.wait(200, function()
    return api.nvim_buf_line_count(restored.bufnr) < 650
  end),
  'Restored history was not compacted'
)
history.toggle(restored)
assert(contains(0, 'Response'), 'Restored archive is empty')
key('q')

-- ACP replays the session after the saved chat has already been opened and
-- trimmed. Exercise that second render, not just the initial ChatCreated event.
local replay = {}
for index = 1, 30 do
  replay[#replay + 1] = {
    sessionUpdate = 'user_message_chunk',
    content = { type = 'text', text = 'Restored prompt ' .. index },
  }
  replay[#replay + 1] = {
    sessionUpdate = 'agent_message_chunk',
    content = {
      type = 'text',
      text = string.rep('Restored response ' .. index .. '\n', 180),
    },
  }
end
require('codecompanion.interactions.chat.acp.render').restore_session(
  restored,
  replay
)
local replayed = lines(restored.bufnr)
local replay_messages = vim.deepcopy(restored.messages)
api.nvim_exec_autocmds('User', {
  pattern = 'CodeCompanionACPChatRestored',
  data = { bufnr = restored.bufnr },
})
assert(
  vim.wait(200, function()
    return api.nvim_buf_line_count(restored.bufnr) < 650
  end),
  'ACP replay left older history in the main buffer'
)
local recent = lines(restored.bufnr)
eq(
  restored.messages,
  replay_messages,
  'Trimming ACP replay changed model messages'
)
assert(
  not contains(restored.bufnr, 'Restored prompt 1\n'),
  'Old prompt remains in the main buffer'
)
history.toggle(restored)
local replay_archive = api.nvim_get_current_buf()
press('999H')
local archived = {}
repeat
  vim.list_extend(archived, vim.list_slice(lines(replay_archive), 5))
  local heading = lines(replay_archive)[1]
  key('L')
  if lines(replay_archive)[1] == heading then
    break
  end
until false
eq(
  vim.list_extend(archived, recent),
  replayed,
  'Replayed history was lost or duplicated'
)
key('q')
eq(lines(restored.bufnr), recent, 'Closing gF expanded the main buffer')
api.nvim_buf_set_lines(restored.bufnr, -1, -1, false, { 'After replay' })
eq(
  parser.messages(restored, restored.header_line).content,
  'After replay',
  'ACP replay shifted the draft incorrectly'
)
print(
  ('PASS ACP replay: %d -> %d lines; exact transcript reconstruction and draft preserved'):format(
    #replayed,
    #recent
  )
)
restored:clear()
local fixture = {
  '---',
  'model: test',
  '---',
  '',
  '## ' .. restored.ui.roles.user,
  '',
  'Old prompt',
  '',
  '## Assistant',
  '',
}
for _ = 1, 350 do
  fixture[#fixture + 1] = 'old output'
end
vim.list_extend(fixture, {
  '',
  '## ' .. restored.ui.roles.user,
  '',
  'Latest prompt',
  '',
  '## Assistant',
  '',
  '```markdown',
})
for _ = 1, 350 do
  fixture[#fixture + 1] = 'code'
end
vim.list_extend(fixture, { '## ' .. restored.ui.roles.user })
for _ = 1, 350 do
  fixture[#fixture + 1] = 'more code'
end
vim.list_extend(
  fixture,
  { '```', '', '## ' .. restored.ui.roles.user, '', 'Unsent text' }
)
api.nvim_buf_set_lines(restored.bufnr, 0, -1, false, fixture)
restored.header_line = #fixture - 2
history.compact(restored)
eq(
  vim.list_slice(lines(restored.bufnr), 1, 4),
  vim.list_slice(fixture, 1, 4),
  'Settings prefix changed'
)
assert(
  contains(restored.bufnr, 'Latest prompt'),
  'Quoted header caused a partial turn to be archived'
)
assert(
  api.nvim_buf_line_count(restored.bufnr) > 700,
  'Latest large exchange was truncated'
)
eq(
  parser.messages(restored, restored.header_line).content,
  'Unsent text',
  'Prefix shifted prompt incorrectly'
)
restored:close()
print(
  ('PASS history: %d -> %d lines, %.1fms; paging, context, draft, submit, streaming, clear'):format(
    #original,
    #remaining,
    elapsed
  )
)

-- Exercise the real dashboard, buffer mappings and timers with a deterministic
-- app-server transport. No model requests or thread mutations are sent.
local thread_data = {
  a = {
    id = 'a',
    parentThreadId = 'parent',
    agentNickname = 'Reviewer',
    status = { type = 'active' },
    updatedAt = 1,
    delegationPrompt = 'Review the patch\n' .. string.rep('full prompt ', 100),
    turns = {
      {
        id = 'a1',
        status = 'inProgress',
        items = {
          {
            type = 'agentMessage',
            text = 'Checking tests\n' .. string.rep('output\n', 1000),
          },
        },
      },
    },
  },
  b = {
    id = 'b',
    parentThreadId = 'parent',
    agentNickname = 'Explorer',
    status = { type = 'idle' },
    updatedAt = 1,
    delegationPrompt = 'Find the parser',
    turns = {
      {
        id = 'b1',
        status = 'completed',
        items = { { type = 'agentMessage', text = 'Found it' } },
      },
    },
  },
}
local calls, pending = {}, {}
local delayed = false
local fake = {}
function fake:request(method, params, callback)
  calls[#calls + 1] = { method = method, params = params }
  local result
  if method == 'thread/list' then
    eq(
      params.ancestorThreadId,
      'parent',
      'Dashboard is not scoped to current chat'
    )
    result = { data = {}, nextCursor = delayed and 'next-page' or nil }
    for _, id in ipairs({ 'b', 'a' }) do
      local summary = vim.deepcopy(thread_data[id])
      summary.turns = nil
      result.data[#result.data + 1] = summary
    end
  elseif method == 'thread/read' then
    result = {
      thread = vim.deepcopy(
        thread_data[params.threadId] or { id = 'parent', turns = {} }
      ),
    }
  elseif method == 'thread/resume' then
    result = { model = 'test-model', reasoningEffort = 'high' }
  else
    error('Unexpected request: ' .. method)
  end
  if delayed then
    pending[#pending + 1] = function()
      callback(result)
    end
  else
    vim.schedule(function()
      callback(result)
    end)
  end
end
function fake:stop() end
package.loaded['lpke.plugins.ai.helpers.codex_threads.client'] = {
  get = function()
    return fake
  end,
  stop_all = function() end,
}
package.loaded['lpke.plugins.ai.helpers.acp_lifecycle'] = {
  get_session_id = function()
    return 'parent'
  end,
}
local source_chat = { adapter = { name = 'codex', type = 'acp' } }
Chat.buf_get_chat = function()
  return source_chat
end
local agents = require('lpke.plugins.ai.helpers.codex_threads')
local formatter = require('lpke.plugins.ai.helpers.codex_threads.format')
eq(
  formatter.delegated_prompt({
    source = { subAgent = { thread_spawn = { prompt = 'Spawn task' } } },
  }),
  'Spawn task',
  'Sparse prompt fields were skipped'
)
agents.setup()
local function settle()
  vim.wait(180, function()
    return false
  end)
end
local source_win, original_windows =
  api.nvim_get_current_win(), #api.nvim_list_wins()
agents.toggle()
settle()
local dashboard, panel = api.nvim_get_current_buf(), api.nvim_get_current_win()
check_hints(dashboard)
assert(contains(dashboard, '1 running · 1 finished'), 'Wrong status counts')
assert(
  api.nvim_buf_line_count(dashboard) < 25,
  'Overview includes full transcripts'
)
for _, call in ipairs(calls) do
  assert(call.method ~= 'thread/resume', 'Overview resumed a thread')
end
local function select_agent(label)
  for row, line in ipairs(lines(dashboard)) do
    if line:find(label, 1, true) then
      api.nvim_win_set_cursor(panel, { row, 0 })
      return
    end
  end
  error('Missing agent: ' .. label)
end
select_agent('Reviewer')
local reviewer_row = api.nvim_win_get_cursor(panel)[1]
key('J')
assert(
  api.nvim_get_current_line():find('Explorer', 1, true),
  'J missed next agent'
)
key('K')
eq(
  api.nvim_win_get_cursor(panel),
  { reviewer_row, 0 },
  'K missed previous agent'
)
press('j')
local free_cursor = api.nvim_win_get_cursor(panel)
assert(free_cursor[1] > reviewer_row, 'j did not move freely')
press('k')
eq(api.nvim_win_get_cursor(panel)[1], reviewer_row, 'k did not move freely')
api.nvim_win_set_cursor(panel, { reviewer_row + 2, 9 })
free_cursor = api.nvim_win_get_cursor(panel)
local tick = api.nvim_buf_get_changedtick(dashboard)
key('r')
settle()
eq(
  api.nvim_buf_get_changedtick(dashboard),
  tick,
  'Unchanged refresh rewrote buffer'
)
eq(api.nvim_win_get_cursor(panel), free_cursor, 'Refresh snapped the cursor')
thread_data.a.turns[1].items[1].text = 'Updated output: '
  .. thread_data.a.turns[1].items[1].text
key('r')
settle()
eq(
  api.nvim_win_get_cursor(panel),
  free_cursor,
  'Changed refresh snapped the cursor'
)
assert(
  api.nvim_buf_get_changedtick(dashboard) > tick,
  'Changed refresh did not update the buffer'
)

key('<CR>')
settle()
eq(api.nvim_get_current_win(), panel, 'Inspect created another split')
local detail = api.nvim_get_current_buf()
check_hints(detail)
assert(contains(detail, thread_data.a.delegationPrompt), 'Full prompt missing')
assert(contains(detail, 'test-model'), 'Execution settings missing')
assert(api.nvim_buf_line_count(detail) > 1000, 'Full output missing')
key('<Esc>')
eq(api.nvim_get_current_buf(), dashboard, 'Escape lost dashboard scope')
key('<CR>')
settle()
key('q')
eq(api.nvim_get_current_buf(), dashboard, 'q lost dashboard scope')
assert(not api.nvim_buf_is_valid(detail), 'Transcript leaked')
key('h')
assert(not contains(dashboard, 'Explorer'), 'Finished run not hidden')
assert(
  contains(dashboard, '[h] show finished'),
  'Hidden hint does not describe the next toggle'
)
key('h')
assert(contains(dashboard, 'Explorer'), 'h did not restore finished runs')
assert(
  contains(dashboard, '[h] hide finished'),
  'Visible hint does not describe the next toggle'
)
assert(
  vim.fn.maparg('u', 'n', false, true).buffer ~= 1,
  'Old u binding remains'
)
key('h')
thread_data.b.updatedAt = 2
thread_data.b.status.type = 'active'
-- The live status must override the old completed turn until hydration catches up.
key('r')
settle()
assert(contains(dashboard, 'Explorer'), 'Restarted agent stayed hidden')
assert(contains(dashboard, '2 running'), 'Restarted agent shown as completed')
key('h')
select_agent('Reviewer')
key('<CR>')
settle()
key('gA')
assert(
  not api.nvim_buf_is_valid(dashboard),
  'gA did not close panel from detail'
)
eq(#api.nvim_list_wins(), original_windows, 'Closing panel left an extra split')
agents.toggle()
settle()
dashboard = api.nvim_get_current_buf()
api.nvim_set_current_win(source_win)
agents.toggle()
assert(
  not api.nvim_buf_is_valid(dashboard),
  'gA from source chat did not toggle off'
)
agents.toggle()
settle()
dashboard = api.nvim_get_current_buf()
delayed = true
key('r')
local call_count = #calls
key('gA')
for _, callback in ipairs(pending) do
  callback()
end
settle()
eq(#calls, call_count, 'Closed dashboard continued hydration')
assert(not api.nvim_buf_is_valid(dashboard), 'Closed dashboard was resurrected')
print(
  'PASS subagents: scope, counts, bounded overview, unchanged refresh, inspect/back, hidden reruns, toggle, pending cleanup'
)
