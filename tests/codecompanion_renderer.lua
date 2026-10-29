-- Run with the isolated runner: --headless -u NONE -l tests/codecompanion_renderer.lua
table.unpack = table.unpack or unpack
vim.opt.rtp:prepend(vim.fn.getcwd())
for _, plugin in ipairs({
  'codecompanion.nvim',
  'plenary.nvim',
  'nvim-treesitter',
}) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end
vim.o.columns, vim.o.lines = 160, 48
Lpke_theme_colors = { muted = '#6e6a86' }
require('codecompanion').setup({
  display = {
    chat = {
      start_in_insert_mode = false,
      show_settings = false,
      auto_scroll = false,
      fold_reasoning = false,
      show_header_separator = false,
    },
  },
  interactions = {
    chat = {
      adapter = 'ollama',
      roles = { user = 'Me', llm = 'Assistant' },
      opts = { completion_provider = 'default' },
    },
  },
})
local render = require('lpke.plugins.ai.helpers.chat_render')
render.patch()
local builder = require('codecompanion.interactions.chat.ui.builder')
local patched_write = builder._write
render.patch()
assert(
  builder._write == patched_write,
  'Repeated setup wrapped the builder twice'
)
require('lpke.plugins.ai.helpers.reasoning_separators').patch()
require('lpke.plugins.ai.helpers.folds').setup()

local api = vim.api
local Chat = require('codecompanion.interactions.chat')
local Handler = require('codecompanion.interactions.chat.acp.handler')
local namespace = api.nvim_get_namespaces()['lpke-codecompanion-reasoning']
local checks = 0
local function eq(actual, expected, message)
  checks = checks + 1
  assert(
    vim.deep_equal(actual, expected),
    (message or 'Mismatch')
      .. '\n'
      .. vim.inspect(actual)
      .. '\nExpected: '
      .. vim.inspect(expected)
  )
end
local function lines(chat)
  return api.nvim_buf_get_lines(chat.bufnr, 0, -1, false)
end
local function new_chat()
  local chat = assert(Chat.new({
    adapter = 'ollama',
    buffer_context = {
      bufnr = api.nvim_get_current_buf(),
      filetype = 'lua',
      lines = {},
    },
  }))
  chat:add_buf_message({ role = 'user', content = 'Prompt' })
  return chat
end
local function reasoning(chat, content)
  return chat:add_buf_message(
    { role = 'llm', content = content },
    { type = chat.MESSAGE_TYPES.REASONING_MESSAGE }
  )
end
local function row_of(chat, text)
  for index, line in ipairs(lines(chat)) do
    if line == text then
      return index - 1
    end
  end
  error('Missing line: ' .. text)
end

local chat = new_chat()
reasoning(chat, 'First thought')
reasoning(chat, '\nSecond thought')
chat:add_buf_message({
  role = 'llm',
  content = 'Answer\n\n```lua\nreturn true\n```',
})
chat:ready_for_input()
api.nvim_buf_set_lines(chat.bufnr, -1, -1, false, { 'Draft' })
eq(lines(chat), {
  '## Me',
  '',
  'Prompt',
  '',
  '## Assistant',
  '',
  'First thought',
  'Second thought',
  'Answer',
  '',
  '```lua',
  'return true',
  '```',
  '',
  '## Me',
  '',
  '',
  'Draft',
}, 'Baseline transcript/draft spacing changed')
local marks =
  api.nvim_buf_get_extmarks(chat.bufnr, namespace, 0, -1, { details = true })
eq(#marks, 2, 'Reasoning chunks need highlights')
for index, mark in ipairs(marks) do
  eq(mark[2], index + 5, 'Reasoning row differs')
  eq(mark[4].end_row, mark[2], 'Reasoning highlight crossed rows')
  eq(mark[4].hl_group, 'LpkeCodeCompanionReasoning')
  eq(mark[4].priority, 210)
end
local hl =
  api.nvim_get_hl(0, { name = 'LpkeCodeCompanionReasoning', link = false })
eq(
  { hl.fg, hl.bold, hl.italic, hl.nocombine },
  { 0x6e6a86, true, nil, true },
  'Reasoning style changed'
)
chat:clear()
eq(
  #api.nvim_buf_get_extmarks(chat.bufnr, namespace, 0, -1, {}),
  0,
  'Clear retained reasoning marks'
)
chat:close()

chat = new_chat()
reasoning(chat, 'Joined')
reasoning(chat, ' thought\n\nnext')
chat:add_buf_message({
  role = 'llm',
  content = '### Reasoning\n### Response\n```markdown\n### Reasoning\n```',
}, { type = chat.MESSAGE_TYPES.LLM_MESSAGE })
eq(lines(chat), {
  '## Me',
  '',
  'Prompt',
  '',
  '## Assistant',
  '',
  'Joined thought',
  '',
  'next',
  '',
  '### Reasoning',
  '### Response',
  '```markdown',
  '### Reasoning',
  '```',
}, 'Content headings or typed block spacing changed')
marks =
  api.nvim_buf_get_extmarks(chat.bufnr, namespace, 0, -1, { details = true })
for _, mark in ipairs(marks) do
  assert(lines(chat)[mark[2] + 1] ~= '', 'Blank reasoning row highlighted')
  assert(
    mark[2] < row_of(chat, '### Reasoning'),
    'Answer heading was highlighted as reasoning'
  )
end
chat:close()

chat = new_chat()
reasoning(chat, 'Before tool')
local _, icon = chat:add_buf_message(
  { role = 'llm', content = 'Tool completed' },
  { type = chat.MESSAGE_TYPES.TOOL_MESSAGE, status = 'completed' }
)
local icon_ns = require('codecompanion.interactions.chat.ui.icons').ns()
eq(
  api.nvim_buf_get_extmark_by_id(chat.bufnr, icon_ns, icon, {})[1],
  row_of(chat, 'Tool completed'),
  'Tool icon shifted off content'
)
chat:add_buf_message(
  { role = 'llm', content = 'Fold summary\nTool detail' },
  { type = chat.MESSAGE_TYPES.TOOL_MESSAGE }
)
vim.wait(30, function()
  return false
end)
local summaries = chat.ui.folds.fold_summaries[chat.bufnr]
eq(
  summaries[row_of(chat, 'Fold summary')].content,
  'Fold summary',
  'Tool fold shifted off content'
)
assert(
  vim.fn
    .foldtextresult(row_of(chat, 'Fold summary') + 1)
    :find('Fold summary', 1, true),
  'Tool fold summary text missing'
)
reasoning(chat, 'After tool')
chat:add_buf_message(
  { role = 'llm', content = 'Final' },
  { type = chat.MESSAGE_TYPES.LLM_MESSAGE }
)
eq(lines(chat), {
  '## Me',
  '',
  'Prompt',
  '',
  '## Assistant',
  '',
  'Before tool',
  '',
  'Tool completed',
  'Fold summary',
  'Tool detail',
  '',
  'After tool',
  '',
  'Final',
}, 'Repeated tools or reasoning re-entry spacing changed')
eq(
  chat.builder.state.current_header_line,
  row_of(chat, '## Assistant'),
  'Role header offset differs'
)
chat:ready_for_input()
eq(chat.header_line, #lines(chat) - 2, 'Draft header parser anchor differs')
vim.cmd('normal! zE')
vim.cmd('1,3fold')
assert(
  vim.fn.foldtextresult(1):find('## Me', 1, true),
  'Ordinary manual fold lost native fold text'
)
chat:close()

-- Highlight byte ranges must include UTF-8 continuations, reuse marks on the
-- same streamed row, and leave literal headings in user content untouched.
chat = new_chat()
reasoning(chat, 'é')
local first_mark =
  api.nvim_buf_get_extmarks(chat.bufnr, namespace, 0, -1, {})[1]
reasoning(chat, '🙂\n漢字')
marks =
  api.nvim_buf_get_extmarks(chat.bufnr, namespace, 0, -1, { details = true })
eq(#marks, 2, 'Continuation duplicated a reasoning extmark')
eq(marks[1][1], first_mark[1], 'Continuation replaced the row extmark')
eq(marks[1][4].end_col, #'é🙂', 'UTF-8 reasoning range uses byte columns')
eq(marks[2][4].end_col, #'漢字', 'Multibyte reasoning range excludes padding')
chat:add_buf_message({ role = 'user', content = '### Reasoning\n### Response' })
eq(
  vim.list_slice(lines(chat), #lines(chat) - 1),
  { '### Reasoning', '### Response' },
  'Literal user headings were removed'
)
chat:close()

-- Compaction must move the active builder anchors and retain recent reasoning
-- styling while clearing marks belonging to archived turns.
local history = require('lpke.plugins.ai.helpers.chat_history')
history.setup()
chat = new_chat()
for index = 1, 10 do
  chat:add_buf_message({ role = 'user', content = 'Long prompt ' .. index })
  reasoning(chat, string.rep('Thought ' .. index .. '\n', 70))
  chat:add_buf_message(
    { role = 'llm', content = string.rep('Answer ' .. index .. '\n', 70) },
    { type = chat.MESSAGE_TYPES.LLM_MESSAGE }
  )
end
chat:ready_for_input()
local prior_marks = #api.nvim_buf_get_extmarks(chat.bufnr, namespace, 0, -1, {})
history.compact(chat)
assert(#lines(chat) < 600, 'Reasoning chat was not compacted')
marks =
  api.nvim_buf_get_extmarks(chat.bufnr, namespace, 0, -1, { details = true })
assert(
  #marks > 0 and #marks < prior_marks,
  'Reasoning marks were lost or archived marks leaked'
)
for _, mark in ipairs(marks) do
  assert(
    lines(chat)[mark[2] + 1]:find('Thought ', 1, true),
    'Compacted reasoning mark shifted onto another block'
  )
end
eq(
  lines(chat)[chat.builder.state.current_header_line + 1],
  '## Me',
  'Compacted builder header differs'
)
chat:close()

-- Every split position must preserve separators even when the comment or its
-- leading whitespace arrives in a later transport chunk.
local text = 'alpha\n\n<!-- -->\n\n<!-- -->\n  beta'
for split = 1, #text - 1 do
  chat = new_chat()
  local handler = Handler.new(chat)
  handler:handle_thought_chunk(text:sub(1, split))
  handler:handle_thought_chunk(text:sub(split + 1))
  handler:handle_message_chunk('Answer')
  eq(
    table.concat(handler.reasoning),
    'alpha\n  beta',
    'Reasoning separator split ' .. split
  )
  eq(lines(chat), {
    '## Me',
    '',
    'Prompt',
    '',
    '## Assistant',
    '',
    'alpha',
    '  beta',
    '',
    'Answer',
  }, 'Rendered separator split ' .. split)
  chat:close()
end

-- The active v20 write path must preserve partial text when any transition
-- flushes a held separator prefix. Stub only transition bodies here.
local module = 'codecompanion.interactions.chat.acp.handler'
local transitions = {
  'handle_message_chunk',
  'process_tool_call',
  'handle_complete',
  'handle_error',
  '_clear_permission_queue',
}
local calls = {}
local fake = {
  handle_thought_chunk = function(_, value)
    calls[#calls + 1] = value
  end,
}
for _, name in ipairs(transitions) do
  fake[name] = function()
    calls[#calls + 1] = 'transition'
  end
end
package.loaded[module] = fake
require('lpke.plugins.ai.helpers.reasoning_separators').patch()
for _, name in ipairs(transitions) do
  calls = {}
  local handler = setmetatable({}, { __index = fake })
  handler:handle_thought_chunk('thought\n\n<!-')
  handler[name](handler)
  eq(
    table.concat(calls),
    'thought\n\n<!-transition',
    'Pending reasoning lost at ' .. name
  )
end
package.loaded[module] = Handler
print(
  ('PASS renderer: %d checks, exact spacing/content, highlights, tool icons/folds, separator splits and transitions'):format(
    checks
  )
)
