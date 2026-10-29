-- Run with isolated plugin data: run-nvim --headless -u NONE -l tests/nvim_0_12_plugin_deprecations.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:prepend(vim.fn.stdpath('data') .. '/site')
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/nvim-cmp')
vim.o.columns, vim.o.lines = 160, 60

local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function eq(actual, expected, message)
  check(
    vim.deep_equal(actual, expected),
    message
      .. '\n'
      .. vim.inspect(actual)
      .. '\nexpected '
      .. vim.inspect(expected)
  )
end

local deprecations = {}
local deprecate = vim.deprecate
vim.deprecate = function(name, ...)
  deprecations[#deprecations + 1] = debug.traceback(name, 2)
  return deprecate(name, ...)
end

-- Capture the pinned plugin's results before replacing its deprecated calls.
-- These expected results cover surrogate pairs, UTF-8 boundaries and fallbacks.
local position = require('cmp.types.lsp').Position
local cases = {}
for _, text in ipairs({ '', 'ascii', 'a😀é𝄞z', 'é' }) do
  for _, encoding in ipairs({ 'utf-8', 'utf-16', 'utf-32' }) do
    for index = -1, #text + 3 do
      for _, method in ipairs({ 'to_utf8', 'to_utf16', 'to_utf32' }) do
        local pos = { line = 4, character = index }
        cases[#cases + 1] = {
          text = text,
          encoding = encoding,
          method = method,
          position = pos,
          expected = position[method](text, pos, encoding),
        }
      end
    end
  end
end
check(#deprecations > 0, 'baseline reaches deprecated UTF overloads')
deprecations = {}

local compat = require('lpke.plugins.nvim_cmp.compat')
compat.setup()
local patched_open = require('cmp.view.docs_view').open
compat.setup()
check(require('cmp.view.docs_view').open == patched_open, 'setup is idempotent')

for _, case in ipairs(cases) do
  eq(
    position[case.method](case.text, case.position, case.encoding),
    case.expected,
    table.concat({ case.method, case.encoding, case.position.character }, ' ')
  )
end
eq(
  position.to_utf8('a😀é𝄞z', { line = 2, character = 3 }),
  { line = 2, character = 5 },
  'default encoding remains UTF-16'
)
local outside = { line = 2, character = 99 }
check(
  position.to_utf8('a😀é𝄞z', outside, 'utf-16') == outside,
  'out of range byte conversion returns the original position'
)
eq(
  position.to_utf16('a😀é𝄞z', outside, 'utf-8'),
  { line = 2, character = 7 },
  'UTF conversion retains cmp backtracking for invalid byte offsets'
)

local cmp = require('cmp')
cmp.setup({
  window = {
    documentation = {
      border = 'rounded',
      max_width = 50,
      max_height = 8,
      winhighlight = 'NormalFloat:NormalFloat,FloatBorder:FloatBorder',
    },
  },
})
local docs = require('cmp.view.docs_view').new()
local view = { col = 45, row = 5, width = 20, height = 2 }
local document_reads = 0
local function entry(id, documents)
  return {
    id = id,
    get_documentation = function()
      document_reads = document_reads + 1
      return documents
    end,
  }
end
local function open(item)
  docs:open(item, view)
  vim.cmd.redraw()
  check(docs:visible(), 'documentation window opened')
  local win, buf = docs.window.win, docs.window:get_buffer()
  local style = vim.api.nvim_win_get_config(win)
  check(style.width > 0 and style.width <= 50, 'documentation width bounded')
  check(style.height > 0 and style.height <= 8, 'documentation height bounded')
  check(style.relative == 'editor', 'cmp still positions the float')
  check(vim.wo[win].conceallevel == 2, 'documentation conceal level')
  check(vim.bo[buf].filetype == 'cmp_docs', 'docs keep their own filetype')
  return win, buf
end

local markdown = entry(1, {
  '',
  '```lua',
  'local value = 1',
  '```',
  '',
  'Summary',
  '---',
  'Details',
  '',
})
local _, markdown_buf = open(markdown)
local lines = vim.api.nvim_buf_get_lines(markdown_buf, 0, -1, false)
check(
  lines[1] == '```lua' and lines[#lines] == 'Details',
  'edge blanks trimmed'
)
check(lines[2] == 'local value = 1', 'code content retained')
check(lines[6]:match('^─'), 'thematic separator expanded')
check(
  vim.treesitter.highlighter.active[markdown_buf] ~= nil,
  'markdown uses a real Treesitter highlighter'
)
local reads = document_reads
open(markdown)
check(
  document_reads == reads,
  'unchanged entries retain cmp documentation cache'
)

local _, plain_buf = open(entry(2, { '', 'plain documentation', '' }))
eq(
  vim.api.nvim_buf_get_lines(plain_buf, 0, -1, false),
  { 'plain documentation' },
  'plain documentation replaces prior fenced content'
)
local code_win, code_buf = open(entry(3, { '```lua', 'return "😀"', '```' }))
check(
  vim.api.nvim_buf_get_lines(code_buf, 1, 2, false)[1] == 'return "😀"',
  'code-only documentation preserves Unicode'
)
check(
  vim.api.nvim_win_get_height(code_win) == 1,
  'concealed fences do not add blank rows'
)

local long = {}
for i = 1, 40 do
  long[i] = 'line ' .. i
end
local long_win = open(entry(4, long))
docs:scroll(4)
check(
  vim.wait(1000, function()
    return vim.fn.getwininfo(long_win)[1].topline > 1
  end),
  'existing cmp documentation scrolling still works'
)
check(docs.window.thumb_win ~= nil, 'existing cmp scrollbar remains available')

-- A missing Markdown parser still produces readable docs with Vim syntax.
local start = vim.treesitter.start
vim.treesitter.start = function()
  error('test parser unavailable')
end
local _, fallback_buf = open(entry(5, { 'fallback text' }))
vim.treesitter.start = start
check(
  vim.bo[fallback_buf].syntax == 'markdown',
  'missing parser syntax fallback'
)
docs:open(entry(6, {}), view)
check(not docs:visible(), 'empty documentation closes the window')
open(entry(7, { 'final document' }))
docs:open(nil, view)
check(not docs:visible(), 'clearing the entry closes the window')

check(
  #deprecations == 0,
  'patched flows call deprecated APIs:\n' .. table.concat(deprecations, '\n')
)
print(
  ('PASS %d plugin checks, %d UTF cases, zero deprecations'):format(
    checks,
    #cases
  )
)
vim.cmd('qa!')
