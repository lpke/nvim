-- run-nvim --headless -u NONE -l tests/codecompanion_layout.lua
local h = dofile('tests/helpers/codecompanion_common.lua')
local api = vim.api
local fns = require('lpke.plugins.ai.helpers.chat_functions')
local cc = require('codecompanion')
local config = require('codecompanion.config')
vim.o.columns, vim.o.lines = 160, 48
vim.cmd.runtime('plugin/codecompanion.lua')
require('lpke.plugins.ai.helpers.keymaps').setup()
local source = api.nvim_create_buf(true, false)
api.nvim_buf_set_name(source, vim.fn.tempname() .. ' source.lua')
vim.bo[source].filetype = 'lua'
api.nvim_buf_set_lines(
  source,
  0,
  -1,
  false,
  { 'local before = 1', 'local value = 2', 'local after = 3' }
)
api.nvim_set_current_buf(source)
local source_win = api.nvim_get_current_win()
local function text(chat)
  return table.concat(api.nvim_buf_get_lines(chat.bufnr, 0, -1, false), '\n')
end
fns.toggle_chat()
local sidebar = cc.buf_get_chat(0)
h.check(sidebar ~= nil, 'sidebar opens actual chat')
h.equal(sidebar.adapter.type, 'acp', 'configured chats use ACP')
h.check(api.nvim_win_get_width(0) < vim.o.columns, 'sidebar width')
fns.toggle_chat()
h.equal(api.nvim_get_current_buf(), source, 'sidebar hides back to source')
fns.toggle_chat()
h.equal(cc.buf_get_chat(0), sidebar, 'sidebar reused')
fns.open_new_chat({ from_chat_keymap = true })
local fresh = cc.buf_get_chat(0)
h.check(fresh and fresh ~= sidebar, 'gn creates a fresh chat')
fns.open_fullscreen_chat()
h.check(fns.is_detached_chat_buf(fresh.bufnr), 'sidebar detached into tab')
h.equal(vim.wo.number, false, 'detached numbers disabled')
h.equal(vim.wo.relativenumber, false, 'detached relative numbers disabled')
h.equal(api.nvim_win_get_width(0), vim.o.columns, 'detached fills tab')
local detached_win = api.nvim_get_current_win()
local detached_tabs = #api.nvim_list_tabpages()
fns.open_fullscreen_chat()
h.equal(
  #api.nvim_list_tabpages(),
  detached_tabs,
  'fullscreen invocation reuses detached tab'
)
api.nvim_set_current_win(source_win)
fns.open_fullscreen_chat()
local second = cc.buf_get_chat(0)
h.check(second and second ~= fresh, 'source creates another fullscreen chat')
h.equal(
  #api.nvim_list_tabpages(),
  detached_tabs + 1,
  'new fullscreen owns another tab'
)
fns.focus_detached_chat(fresh)
h.equal(api.nvim_get_current_win(), detached_win, 'existing detached focus')
fns.swap_chat(fresh, -1)
h.check(cc.buf_get_chat(0) ~= fresh, 'chat cycling changes chat')
fns.focus_detached_chat(second)
api.nvim_buf_set_lines(second.bufnr, -1, -1, false, { 'kept draft' })
local restore = fns.restore_context_from_current()
h.equal(restore.source_detached, true, 'restore captures detached source')
h.equal(restore.close_source, false, 'nonempty source is retained')
fns.after_restore(sidebar, restore)
h.equal(cc.buf_get_chat(0), sidebar, 'restored target receives focus')
h.check(
  fns.is_detached_chat_buf(sidebar.bufnr),
  'restore retains detached layout'
)
h.check(api.nvim_buf_is_valid(second.bufnr), 'occupied restore source survives')
api.nvim_set_current_win(source_win)
fns.take_restore_context()
fns.after_restore(sidebar)
h.equal(
  cc.buf_get_chat(0),
  sidebar,
  'already-visible restore target receives focus'
)

-- Real native context rows determine whether a draft is actually empty.
local draft = h.chat()
local source_context =
  require('lpke.plugins.ai.helpers.editor_context.buffer').new({
    Chat = draft,
    params = 'diff',
  })
source_context:chat_render({ bufnr = source })
h.check(
  require('lpke.plugins.ai.helpers.chat_draft').empty(draft),
  'sync-diff context-only draft is empty'
)
api.nvim_buf_set_lines(draft.bufnr, -1, -1, false, { '> quoted draft remains' })
h.equal(
  require('lpke.plugins.ai.helpers.chat_draft').empty(draft),
  false,
  'user blockquote is not synthetic context'
)
h.equal(
  fns.is_empty_chat(draft.bufnr),
  false,
  'cleanup preserves a quoted draft'
)
local heading_draft = h.chat()
api.nvim_buf_set_lines(
  heading_draft.bufnr,
  -1,
  -1,
  false,
  { '## Real prompt heading' }
)
h.equal(
  fns.is_empty_chat(heading_draft.bufnr),
  false,
  'cleanup preserves a heading-only draft'
)
local transcript = h.chat()
transcript:add_message({ role = 'user', content = 'existing conversation' })
h.equal(
  fns.is_empty_chat(transcript.bufnr),
  false,
  'empty current draft does not discard conversation'
)
local reasoning = h.chat()
reasoning:add_message({ role = 'llm', reasoning = 'existing reasoning' })
h.equal(
  fns.is_empty_chat(reasoning.bufnr),
  false,
  'reasoning-only conversation is retained'
)
local sync_all_draft = h.chat()
require('lpke.plugins.ai.helpers.editor_context.buffer')
  .new({ Chat = sync_all_draft, params = 'all' })
  :chat_render({ bufnr = source })
h.check(
  require('lpke.plugins.ai.helpers.chat_draft').empty(sync_all_draft),
  'sync-all context-only draft is empty'
)
h.equal(
  fns.build_code_block('one\ntwo\n', 'lua'),
  { '```lua', 'one', 'two', '```' },
  'visual selection fence trims one final newline'
)

api.nvim_set_current_win(source_win)
api.nvim_win_set_buf(source_win, source)
api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('normal! v4l')
fns.open_new_chat_with_context_selection()
h.check(
  text(cc.buf_get_chat(0)):find('```lua\nlocal\n```', 1, true),
  'character selection is fenced exactly'
)
api.nvim_set_current_win(source_win)
api.nvim_win_set_buf(source_win, source)
api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('normal! Vj')
fns.open_fullscreen_chat_with_context_selection()
h.check(
  text(cc.buf_get_chat(0)):find(
    '```lua\nlocal before = 1\nlocal value = 2\n```',
    1,
    true
  ),
  'line selection is fenced exactly'
)
h.check(
  fns.is_detached_chat_buf(api.nvim_get_current_buf()),
  'selected fullscreen layout'
)
api.nvim_set_current_win(source_win)
api.nvim_win_set_buf(source_win, source)
api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('normal! ' .. vim.keycode('<C-v>') .. 'j4l')
fns.toggle_chat_with_context_selection()
h.check(
  text(cc.buf_get_chat(0)):find('```lua\nlocal\nlocal\n```', 1, true),
  'block selection is fenced exactly'
)

local source_path = api.nvim_buf_get_name(source) .. ' `quoted`'
api.nvim_buf_set_name(source, source_path)
api.nvim_set_current_win(source_win)
api.nvim_win_set_buf(source_win, source)
api.nvim_set_current_win(detached_win)
api.nvim_win_set_buf(detached_win, fresh.bufnr)
api.nvim_buf_set_lines(fresh.bufnr, -1, -1, false, { '' })
api.nvim_win_set_cursor(0, { api.nvim_buf_line_count(fresh.bufnr), 0 })
fns.insert_last_source_path()
h.equal(
  api.nvim_get_current_line(),
  '`' .. source_path:gsub('`', '\\`') .. '`',
  'last source path escapes backticks'
)
local oil = api.nvim_create_buf(true, false)
api.nvim_buf_set_name(oil, 'oil:///fixture directory/')
vim.bo[oil].filetype = 'oil'
package.loaded.oil = {
  get_current_dir = function()
    return '/fixture directory/'
  end,
}
api.nvim_set_current_win(source_win)
api.nvim_win_set_buf(source_win, oil)
api.nvim_set_current_win(detached_win)
api.nvim_buf_set_lines(fresh.bufnr, -1, -1, false, { '' })
api.nvim_win_set_cursor(0, { api.nvim_buf_line_count(fresh.bufnr), 0 })
fns.insert_last_source_path()
h.equal(
  api.nvim_get_current_line(),
  '`/fixture directory/`',
  'Oil inserts its directory path'
)
api.nvim_buf_delete(oil, { force = true })
if not api.nvim_win_is_valid(source_win) then
  vim.cmd.vsplit()
  source_win = api.nvim_get_current_win()
end
api.nvim_set_current_win(source_win)
api.nvim_win_set_buf(source_win, source)
api.nvim_set_current_win(detached_win)
api.nvim_buf_set_lines(fresh.bufnr, -1, -1, false, { '' })
api.nvim_win_set_cursor(0, { api.nvim_buf_line_count(fresh.bufnr), 0 })
fns.insert_last_source_path()
h.equal(
  api.nvim_get_current_line(),
  '`' .. source_path:gsub('`', '\\`') .. '`',
  'wiped last source falls back to a visible source'
)
local victim = h.chat()
victim.ui:open()
fns.delete_current_chat(victim)
h.check(not api.nvim_buf_is_valid(victim.bufnr), 'deleted chat buffer removed')
h.check(cc.buf_get_chat(0) ~= nil, 'deleting chat focuses another live chat')
local default_adapter = config.interactions.chat.adapter
config.interactions.chat.adapter = 'fixture'
vim.cmd.tabnew()
api.nvim_set_current_buf(source)
fns.open_new_chat()
local http_chat = cc.buf_get_chat(0)
h.equal(
  http_chat.adapter.type,
  'http',
  'shared new-chat layout also accepts native HTTP adapters'
)
h.check(
  not text(http_chat):find('@{', 1, true),
  'HTTP chats receive no custom tool tags'
)
fns.open_fullscreen_chat()
h.equal(cc.buf_get_chat(0), http_chat, 'HTTP detach retains chat identity')
h.check(
  fns.is_detached_chat_buf(http_chat.bufnr),
  'HTTP chat uses the same detached ownership'
)
config.interactions.chat.adapter = default_adapter
h.equal(fns.insert_http_tools, nil, 'obsolete HTTP tool injection API removed')
h.done('shared layout/selection/source helpers')
