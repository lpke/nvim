-- run-nvim --headless -u NONE -l tests/codecompanion_inline.lua
-- Only the outbound HTTP boundary is replaced; native edits and diff decisions run.
table.unpack = table.unpack or unpack
vim.opt.rtp:prepend(vim.fn.getcwd())
for _, name in ipairs({
  'codecompanion.nvim',
  'plenary.nvim',
  'nvim-treesitter',
}) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. name)
end
vim.opt.rtp:prepend(vim.fn.stdpath('data') .. '/site')
require('lpke.core.globals')
local api = vim.api
local checks, notices = 0, {}
local function equal(actual, expected, message)
  checks = checks + 1
  assert(
    vim.deep_equal(actual, expected),
    message
      .. '\n'
      .. vim.inspect(actual)
      .. '\nexpected: '
      .. vim.inspect(expected)
  )
end
local function check(value, message)
  equal(not not value, true, message)
end
local function wait(predicate, message)
  check(vim.wait(3000, predicate, 10), message)
end
vim.notify = function(message)
  notices[#notices + 1] = message
end
require('codecompanion').setup({
  adapters = {
    http = {
      fixture = function()
        return require('codecompanion.adapters').extend('openai_compatible', {
          name = 'fixture',
          formatted_name = 'Fixture',
          opts = { tools = true, stream = true },
          schema = { model = { default = 'fixture', choices = { 'fixture' } } },
        })
      end,
    },
  },
  interactions = {
    inline = { adapter = 'fixture' },
    chat = { opts = { completion_provider = 'default' } },
  },
  rules = { opts = { inline = { autoload = false } } },
  skills = { opts = { inline = { autoload = false } } },
})
local requests = {}
require('codecompanion.http').new = function()
  return {
    send = function(_, payload, callbacks)
      local request = { payload = vim.deepcopy(payload), callbacks = callbacks }
      requests[#requests + 1] = request
      return {
        cancel = function()
          request.cancelled = true
        end,
      }
    end,
  }
end
local input = require('codecompanion.interactions.shared.input')
local fns = require('lpke.plugins.ai.helpers.chat_functions')
local approvals = require('codecompanion.interactions.chat.tools.approvals')
local function source(lines)
  input.hide()
  vim.cmd.stopinsert()
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_name(buf, vim.fn.tempname() .. '.lua')
  vim.bo[buf].filetype = 'lua'
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  approvals:set_mode(buf, { mode = 'ask' })
  return buf
end
local function begin(visual)
  local inline =
    fns.open_inline_prompt_with_context(visual and { visual = true } or nil)
  check(inline ~= nil, 'native inline object created')
  input.set_content('Change the selected code')
  vim.cmd.write()
  return inline, requests[#requests]
end
local function call(old, new)
  return {
    ['function'] = {
      name = 'edit_file',
      arguments = { old_string = old, new_string = new, replace_all = false },
    },
  }
end
local function fails(inline, old)
  local before = inline.request.edited
  local result = inline.request:apply_edits({ call(old, 'outside mutation') })
  check(result[1].error ~= nil, 'unselected text rejected: ' .. old)
  equal(
    inline.request.edited,
    before,
    'failed edit leaves selected text intact'
  )
end
local function reply(request, old, new)
  local args = call(old, new)['function'].arguments
  request.callbacks.on_chunk('data: ' .. vim.json.encode({
    choices = {
      {
        delta = {
          role = 'assistant',
          tool_calls = {
            {
              index = 0,
              id = 'edit-fixture',
              type = 'function',
              ['function'] = {
                name = 'edit_file',
                arguments = vim.json.encode(args),
              },
            },
          },
        },
      },
    },
  }))
  request.callbacks.on_done()
end
local function accept(inline)
  wait(function()
    return inline.diff_ui ~= nil
  end, 'native diff opens')
  require('codecompanion.diff.keymaps').accept_change.callback(inline.diff_ui)
end

-- Astra's exact partial-line probe: the comment is inside the native line target
-- but outside the user's selected character span.
local original = { 'local value = 2 -- keep me', 'local trailing = 3' }
local buf = source(original)
api.nvim_win_set_cursor(0, { 1, 6 })
vim.cmd('normal! v4l')
local inline, request = begin(true)
equal(inline.buffer_context.code, 'value', 'exact character selection')
equal(inline.request.edited, 'value', 'tool matches selection only')
fails(inline, 'keep me')
fails(inline, 'local')
reply(request, 'value', 'renamed')
accept(inline)
equal(
  api.nvim_buf_get_lines(buf, 0, -1, false),
  { 'local renamed = 2 -- keep me', original[2] },
  'prefix, suffix and other lines preserved after native accept'
)

-- Native retry receives the failed edit, then a valid retry can still be rejected.
buf = source(original)
api.nvim_win_set_cursor(0, { 1, 6 })
vim.cmd('normal! v4l')
inline, request = begin(true)
local count = #requests
reply(request, 'keep me', 'wrong')
equal(#requests, count + 1, 'invalid character edit triggers native retry')
check(
  vim.json
    .encode(requests[#requests].payload.messages)
    :find('Edit failed:', 1, true),
  'failed edit reaches retry payload'
)
reply(requests[#requests], 'value', 'replacement')
wait(function()
  return inline.diff_ui ~= nil
end, 'retry opens native diff')
require('codecompanion.diff.keymaps').reject_change.callback(inline.diff_ui)
equal(
  api.nvim_buf_get_lines(buf, 0, -1, false),
  original,
  'native reject preserves entire original buffer'
)

-- A contiguous multi-line character selection may change its own line count.
buf =
  source({ 'untouched before', 'prefix ONE', 'TWO suffix', 'untouched after' })
api.nvim_win_set_cursor(0, { 2, 7 })
vim.cmd('normal! v')
api.nvim_win_set_cursor(0, { 3, 2 })
inline, request = begin(true)
equal(
  inline.request.edited,
  'ONE\nTWO',
  'multi-line selection excludes both edges'
)
fails(inline, 'prefix')
fails(inline, 'suffix')
reply(request, 'ONE\nTWO', 'A\nB\nC')
accept(inline)
equal(
  api.nvim_buf_get_lines(buf, 0, -1, false),
  { 'untouched before', 'prefix A', 'B', 'C suffix', 'untouched after' },
  'multi-line replacement preserves both boundary fragments'
)

-- Rectangular selection protects the prefix/suffix of every row.
buf = source({ 'aafooZZ', 'bbbarYY', 'untouched' })
api.nvim_win_set_cursor(0, { 1, 2 })
vim.cmd('normal! ' .. vim.keycode('<C-v>'))
api.nvim_win_set_cursor(0, { 2, 4 })
inline, request = begin(true)
equal(
  inline.buffer_context.code,
  'foo\nbar',
  'native rectangular selection captured exactly'
)
fails(inline, 'aa')
fails(inline, 'ZZ')
fails(inline, 'bb')
fails(inline, 'YY')
local rejected =
  inline.request:apply_edits({ call('foo\nbar', 'wrong row count') })
check(rejected[1].error ~= nil, 'block row-count changes rejected')
equal(inline.request.edited, 'foo\nbar', 'invalid block edit rolls back')
reply(request, 'foo\nbar', 'ZIP\nZAP')
accept(inline)
equal(
  api.nvim_buf_get_lines(buf, 0, -1, false),
  { 'aaZIPZZ', 'bbZAPYY', 'untouched' },
  'every block edge preserved'
)

-- Inclusive UTF-8 and exclusive/reversed regions use Neovim byte boundaries.
buf = source({ 'left café right' })
api.nvim_win_set_cursor(0, { 1, 8 })
vim.cmd('normal! v')
inline = begin(true)
equal(inline.request.edited, 'é', 'whole UTF-8 character selected')
local result = inline.request:apply_edits({ call('é', 'E') })
equal(result[1].error, nil, 'UTF-8 edit accepted')
equal(
  inline.request:get_new_content(),
  { 'left cafE right' },
  'UTF-8 outside bytes preserved'
)
inline:stop()
vim.o.selection = 'exclusive'
buf = source({ 'prefix value suffix' })
api.nvim_win_set_cursor(0, { 1, 7 })
vim.cmd('normal! v')
api.nvim_win_set_cursor(0, { 1, 12 })
inline = begin(true)
equal(inline.request.edited, 'value', 'exclusive endpoint honored')
inline:stop()
vim.o.selection = 'inclusive'
buf = source({ 'prefix value suffix' })
api.nvim_win_set_cursor(0, { 1, 11 })
vim.cmd('normal! v')
api.nvim_win_set_cursor(0, { 1, 7 })
inline = begin(true)
equal(inline.request.edited, 'value', 'reversed character selection normalized')
inline:stop()

-- Full source and normal edit scope must not be capped by the native token budget.
local lines = {}
for index = 1, 1000 do
  lines[index] = ('local row_%d = %q'):format(
    index,
    ('ordinary_words '):rep(80)
  )
end
buf = source(lines)
api.nvim_win_set_cursor(0, { 500, 0 })
require('codecompanion.config').interactions.inline.opts.max_context_tokens = 1
inline = fns.open_inline_prompt_with_context()
inline.adapter.model = { meta = { context_window = 3100 } }
equal(
  require('codecompanion.adapters.shared').input_limit(inline.adapter),
  3100,
  'adapter input cap is also present'
)
input.set_content('Change first and last lines')
vim.cmd.write()
request = requests[#requests]
equal(
  inline.target.context,
  { first = 1, last = 1000 },
  'all large-buffer context included despite tiny configured budget'
)
equal(
  inline.target.editable,
  { first = 1, last = 1000 },
  'normal editable scope includes entire buffer'
)
local buffers = vim.tbl_filter(function(message)
  return message._meta and message._meta.tag == 'buffer'
end, request.payload.messages)
equal(#buffers, 1, 'full buffer context sent once')
check(
  buffers[1].content:find(lines[1], 1, true),
  'first line reaches outgoing payload'
)
check(
  buffers[1].content:find(lines[1000], 1, true),
  'last line reaches outgoing payload'
)
check(
  not vim.json.encode(request.payload.messages):find('#{buffer}', 1, true),
  'no obsolete token or duplicate expansion'
)
local edits = inline.request:apply_edits({
  call(lines[1], 'local first = true'),
  call(lines[1000], 'local last = true'),
})
equal(
  edits[1].error,
  nil,
  'first line outside native truncated region is editable'
)
equal(
  edits[2].error,
  nil,
  'last line outside native truncated region is editable'
)
local candidate = inline.request:get_new_content()
equal(candidate[1], 'local first = true', 'first normal edit assembled')
equal(candidate[1000], 'local last = true', 'last normal edit assembled')
inline:stop()
check(request.cancelled, 'native cancellation reaches HTTP transport')
equal(inline.requesting, false, 'native cancellation resets request state')

-- ACP's own line guard is followed by exact character boundaries too.
buf = source({ 'local value = 2 -- keep me', 'after' })
api.nvim_win_set_cursor(0, { 1, 6 })
vim.cmd('normal! v4l')
inline = fns.open_inline_prompt_with_context({ visual = true })
inline.target = inline:get_target()
local acp = require('codecompanion.interactions.inline.adapters.acp').new({
  inline = inline,
})
equal(
  acp:keep_editable_changes({ 'local value = 2 -- wrong', 'after' }),
  inline.target.lines,
  'ACP cannot change unselected trailing text'
)
equal(
  acp:keep_editable_changes({ 'local changed = 2 -- keep me', 'after' }),
  { 'local changed = 2 -- keep me', 'after' },
  'ACP selected character change allowed'
)
input.hide()
print(('PASS exact inline scope: %d checks'):format(checks))
vim.cmd('qa!')
