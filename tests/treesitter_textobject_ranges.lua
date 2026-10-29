vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:prepend(vim.fn.stdpath('data') .. '/site')
vim.opt.rtp:append(
  vim.fn.stdpath('data') .. '/lazy/nvim-treesitter-textobjects'
)
require('lpke.plugins.helpers.deprecations').setup()
local shared = require('nvim-treesitter-textobjects.shared')
local checks = 0
local function check(value, label)
  checks = checks + 1
  assert(value, label)
end
local function run(lines, query_text, capture, position)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  local group = 'lpke_textobject_ranges_' .. buf
  vim.treesitter.query.set('python', group, query_text)
  local tree = vim.treesitter.get_parser(buf, 'python'):parse()[1]
  local query = vim.treesitter.query.get('python', group)
  local expected
  for _, match, metadata in query:iter_matches(tree:root(), buf) do
    for id, nodes in pairs(match) do
      if query.captures[id] == capture then
        local first = vim.treesitter.get_range(nodes[1], buf, metadata[id])
        local last = vim.treesitter.get_range(nodes[#nodes], buf, metadata[id])
        expected = { first[1], first[2], first[3], last[4], last[5], last[6] }
      end
    end
  end
  check(expected ~= nil, 'query has a real capture')
  local actual =
    shared.textobject_at_point('@' .. capture, group, buf, position)
  check(
    vim.deep_equal(actual, expected),
    vim.inspect({ actual = actual, expected = expected })
  )
  vim.api.nvim_buf_delete(buf, { force = true })
  return actual
end
local inner = run(
  { '# hello' },
  '((comment) @comment.inner (#offset! @comment.inner 0 2 0 0))',
  'comment.inner',
  { 1, 4 }
)
check(inner[2] == 2 and inner[5] == 7, 'inner comment excludes prefix')
local unicode = run(
  { '# café 😀' },
  '((comment) @comment.inner (#offset! @comment.inner 0 2 0 0))',
  'comment.inner',
  { 1, 5 }
)
check(
  unicode[2] == 2 and unicode[5] == #'# café 😀',
  'Unicode byte offsets preserved'
)
local outer = run(
  { '# hello' },
  '(comment) @comment.outer',
  'comment.outer',
  { 1, 4 }
)
check(outer[2] == 0, 'unmodified captures retain full nodes')
local multiple = run(
  { 'left()', 'right()' },
  '(module (expression_statement) @call.inner (expression_statement) @call.inner (#offset! @call.inner 0 1 0 -1))',
  'call.inner',
  { 1, 3 }
)
check(
  multiple[2] == 1 and multiple[4] == 1 and multiple[5] == 6,
  'multiple captured nodes apply offsets at both ends'
)
print(('PASS textobject ranges: %d checks'):format(checks))
