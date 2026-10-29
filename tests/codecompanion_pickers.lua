-- Real Telescope saved/search/open/draft/summary picker callbacks, offline.
-- nvim --headless -u NONE -l tests/codecompanion_pickers.lua
table.unpack = table.unpack or unpack
local api = vim.api
vim.opt.rtp:prepend(vim.fn.getcwd())
for _, plugin in ipairs({
  'codecompanion.nvim',
  'codecompanion-history.nvim',
  'plenary.nvim',
  'nvim-treesitter',
  'telescope.nvim',
}) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end
require('lpke.core.globals')
vim.o.columns, vim.o.lines = 160, 48
require('telescope').setup({ defaults = { initial_mode = 'normal' } })
local checks = 0
local function eq(actual, expected, label)
  checks = checks + 1
  assert(
    vim.deep_equal(actual, expected),
    label
      .. '\n'
      .. vim.inspect(actual)
      .. '\nexpected '
      .. vim.inspect(expected)
  )
end
local function flush()
  vim.wait(40, function()
    return false
  end)
end
local root, original_cwd = vim.fn.tempname(), vim.fn.getcwd()
for _, name in ipairs({ 'project', 'other' }) do
  vim.fn.mkdir(root .. '/' .. name, 'p')
  vim.fn.writefile({ 'Fixture' }, root .. '/' .. name .. '/README.md')
end
vim.cmd.cd(root .. '/project')
local cc = require('codecompanion')
-- Existing on-disk summaries remain supported without generating HTTP chats.
vim.fn.mkdir(root .. '/history/summaries', 'p')
vim.fn.writefile(
  { 'Fixture summary content' },
  root .. '/history/summaries/alpha.md',
  'b'
)
vim.fn.writefile({
  vim.json.encode({
    alpha = {
      summary_id = 'alpha',
      chat_id = 'alpha',
      chat_title = 'Alpha title',
      generated_at = os.time(),
      project_root = root .. '/project',
    },
  }),
}, root .. '/history/summaries_index.json')
cc.setup({
  display = { chat = { show_settings = false, start_in_insert_mode = false } },
  interactions = {
    chat = { adapter = 'codex', opts = { completion_provider = 'default' } },
  },
  extensions = {
    history = {
      enabled = true,
      opts = {
        dir_to_save = root .. '/history',
        auto_save = false,
        auto_generate_title = false,
        expiration_days = 0,
        picker = 'telescope',
        picker_keymaps = { rename = { n = 'gr', i = '<M-r>' } },
      },
    },
  },
})
local chat_fns = require('lpke.plugins.ai.helpers.chat_functions')
require('lpke.plugins.ai.helpers.history_scope').setup()
require('lpke.plugins.ai.helpers.history_acp').setup()
local search = require('lpke.plugins.ai.helpers.history_search')
search.setup()
local drafts = require('lpke.plugins.ai.helpers.drafts')
drafts.setup()
local history = cc.extensions.history
require('codecompanion.interactions.chat.helpers').create_acp_connection = function(
  chat,
  callback
)
  chat.acp_connection = {
    session_id = chat.acp_session_id,
    is_connected = function()
      return true
    end,
    is_ready = function()
      return true
    end,
    get_models = function()
      return {}
    end,
    get_config_options = function()
      return {}
    end,
    build_name_map = function()
      return {}
    end,
    disconnect = function() end,
  }
  if callback then
    callback()
  end
end
local Chat = require('codecompanion.interactions.chat')
local function new_chat(id, title, text)
  local source = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(source)
  local chat = assert(Chat.new({
    adapter = 'codex',
    save_id = id,
    title = title,
    buffer_context = {
      bufnr = source,
      filetype = 'lua',
      filename = 'fixture.lua',
      lines = {},
    },
    messages = {
      { role = 'user', content = text, opts = { visible = true } },
      {
        role = 'llm',
        content = 'Exact response for ' .. title,
        opts = { visible = true },
      },
      { role = 'user', content = '', opts = { visible = true } },
    },
  }))
  api.nvim_set_current_buf(chat.bufnr)
  flush()
  history.save_chat(chat)
  return chat
end
local alpha = new_chat('alpha', 'Alpha title', 'Needle in the first task')
local beta = new_chat('beta', 'Beta title', 'Other project task')
vim.cmd.cd(root .. '/other')
new_chat('elsewhere', 'Elsewhere', 'Needle outside project')
vim.cmd.cd(root .. '/project')
api.nvim_set_current_buf(alpha.bufnr)
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local function current_picker(expected_count, prefix)
  flush()
  local picker = action_state.get_current_picker(api.nvim_get_current_buf())
  assert(picker, 'Missing picker')
  assert(
    vim.wait(1500, function()
      return picker.manager and picker.manager:num_results() == expected_count
    end),
    'Picker result count, expected '
      .. expected_count
      .. ', got '
      .. tostring(picker.manager and picker.manager:num_results())
  )
  if prefix then
    eq(picker.prompt_title:sub(1, #prefix), prefix, 'Picker title')
  end
  return picker
end
local function select_id(picker, id)
  for index = 1, picker.manager:num_results() do
    local entry = picker.manager:get_entry(index)
    if entry.value.save_id == id or entry.value.path == id then
      picker:set_selection(picker:get_row(index))
      flush()
      return
    end
  end
  error('Missing picker entry ' .. id)
end
local function mapping(lhs)
  local map = vim.fn.maparg(lhs, 'n', false, true)
  assert(type(map.callback) == 'function', 'Missing mapping ' .. lhs)
  map.callback()
  flush()
end
chat_fns.open_history()
local picker = current_picker(2, 'Saved Chats (cwd)')
picker:set_prompt('@*', true)
current_picker(3, 'Saved Chats (all)')
picker:set_prompt('Alpha', true)
current_picker(1)
local old_prompt = picker.prompt_bufnr
local input = vim.ui.input
vim.ui.input = function(_, callback)
  callback('Alpha renamed')
end
mapping('gr')
eq(api.nvim_get_current_buf(), old_prompt, 'Rename retains live picker')
eq(picker:_get_prompt(), 'Alpha', 'Rename retains query')
eq(history.load_chat('alpha').title, 'Alpha renamed', 'Rename persisted')
eq(alpha.opts.title, 'Alpha renamed', 'Rename updates open chat')
vim.ui.input = function(_, callback)
  callback(nil)
end
mapping('gr')
eq(api.nvim_get_current_buf(), old_prompt, 'Cancelled rename retains picker')
vim.ui.input = input

-- Find in Chats has a real preview and selection callback to the matching line.
mapping('<A-s>')
picker = current_picker(1, 'Find in Chats')
eq(picker:_get_prompt(), 'Alpha', 'Saved-to-search toggle retains query')
picker:set_prompt('Needle', true)
picker = current_picker(1)
eq(
  picker.manager:get_entry(1).value.text,
  'Needle in the first task',
  'Current-project content search'
)
assert(
  vim.wait(1000, function()
    return picker.previewer.state.bufnr ~= nil
  end),
  'Search preview absent'
)
local preview = picker.previewer.state.bufnr
eq(
  table
    .concat(api.nvim_buf_get_lines(preview, 0, -1, false), '\n')
    :find('Needle in the first task', 1, true) ~= nil,
  true,
  'Preview contains full match'
)
local namespace =
  api.nvim_get_namespaces().LpkeCodeCompanionHistorySearchPreview
local marks =
  api.nvim_buf_get_extmarks(preview, namespace, 0, -1, { details = true })
eq(
  vim.iter(marks):any(function(mark)
    return mark[4].hl_group == 'LpkeCodeCompanionHistorySearchActiveMatch'
  end),
  true,
  'Active preview match highlighted'
)
actions.select_default(picker.prompt_bufnr)
flush()
eq(
  api.nvim_get_current_buf(),
  alpha.bufnr,
  'Search selection reuses existing chat'
)
eq(
  api.nvim_get_current_line(),
  'Needle in the first task',
  'Search selection jumps to exact match'
)
search.open({ default_text = '@*  Needle' })
picker = current_picker(2, 'Find in Chats')
mapping('<A-s>')
picker = current_picker(2, 'Saved Chats (cwd)')
actions.close(picker.prompt_bufnr)
flush()

-- Inherited duplicate and delete mappings run their actual handlers.
api.nvim_set_current_buf(alpha.bufnr)
chat_fns.open_history()
picker = current_picker(2)
select_id(picker, 'alpha')
vim.ui.input = function(_, callback)
  callback('Alpha duplicate')
end
mapping('<C-y>')
vim.ui.input = input
picker = current_picker(3)
local duplicate_id
for id, item in pairs(history.get_chats()) do
  if item.title == 'Alpha duplicate' then
    duplicate_id = id
  end
end
assert(duplicate_id, 'Duplicate did not save a chat')
select_id(picker, duplicate_id)
local confirm = vim.fn.confirm
vim.fn.confirm = function()
  return 1
end
mapping('d')
vim.fn.confirm = confirm
picker = current_picker(2)
eq(history.load_chat(duplicate_id), nil, 'Delete removes selected saved chat')
select_id(picker, 'beta')
actions.select_default(picker.prompt_bufnr)
flush()
eq(
  api.nvim_get_current_buf(),
  beta.bufnr,
  'Saved-history selection reuses open chat'
)

-- The picker reads the shared request owner, including overlaps/stale finishes.
local request_state = require('lpke.plugins.ai.helpers.request_state')
request_state.setup()
local function request_event(event, id)
  api.nvim_exec_autocmds('User', {
    pattern = 'CodeCompanionRequest' .. event,
    data = { bufnr = alpha.bufnr, id = id, interaction = 'chat' },
  })
end
local function alpha_entry()
  for _, item in
    ipairs(require('lpke.plugins.ai.helpers.chat_picker').build_entries())
  do
    if item.bufnr == alpha.bufnr then
      return item
    end
  end
  error('Alpha absent from open picker entries')
end
request_event('Started', 'a')
request_event('Started', 'b')
eq(
  alpha_entry().display:find('!', 1, true) ~= nil,
  true,
  'Picker visibly marks active requests'
)
request_event('Finished', 'a')
eq(alpha_entry().processing, true, 'Overlapping request keeps picker busy')
request_event('Finished', 'stale')
eq(
  alpha_entry().processing,
  true,
  'Stale finish cannot clear picker busy state'
)
request_event('Finished', 'b')
eq(
  alpha_entry().display:find('!', 1, true),
  nil,
  'Picker clears active marker on exact final completion'
)
request_event('Started', 'stop')
api.nvim_exec_autocmds(
  'User',
  { pattern = 'CodeCompanionChatStopped', data = { bufnr = alpha.bufnr } }
)
eq(alpha_entry().processing, false, 'Stop clears picker busy marker')

-- Open chat picker selection, preview, empty cleanup and selected deletion.
api.nvim_set_current_buf(alpha.bufnr)
local open = require('lpke.plugins.ai.helpers.chat_picker')
local empty = assert(Chat.new({
  adapter = 'codex',
  buffer_context = {
    bufnr = alpha.bufnr,
    filetype = 'lua',
    filename = 'fixture.lua',
    lines = {},
  },
}))
flush()
api.nvim_set_current_buf(alpha.bufnr)
open.open()
picker = current_picker(4, 'CodeCompanion Chats')
mapping('dX')
picker = current_picker(3)
eq(
  cc.buf_get_chat(empty.bufnr),
  nil,
  'Open-picker dX closes empty inactive chat'
)
eq(
  table
    .concat(api.nvim_buf_get_lines(picker.previewer.state.bufnr, 0, -1, false), '\n')
    :find('##', 1, true) ~= nil,
  true,
  'Open chat preview is transcript'
)
select_id = function(target, id)
  for index = 1, target.manager:num_results() do
    if target.manager:get_entry(index).value.bufnr == id then
      target:set_selection(target:get_row(index))
      flush()
      return
    end
  end
  error('Open chat absent')
end
select_id(picker, beta.bufnr)
actions.select_default(picker.prompt_bufnr)
flush()
eq(
  api.nvim_get_current_buf(),
  beta.bufnr,
  'Open picker selects requested live chat'
)

-- Actual Draft Prompts selection appends without replacing current prompt.
local draft_chat = new_chat('draft', 'Draft fixture', 'Earlier sent prompt')
draft_chat:add_buf_message({
  role = 'user',
  content = 'Saved draft quotation\n> retain this',
})
eq(drafts.save(draft_chat.bufnr), true, 'Draft saved')
local draft_path = drafts.list_current_cwd()[1].path
api.nvim_set_current_buf(beta.bufnr)
beta:add_buf_message({ role = 'user', content = 'Existing prompt' })
local original_select = vim.ui.select
vim.ui.select = function(items, opts, callback)
  eq(opts.prompt, 'Chat History', 'gH action chooser')
  callback(items[3])
end
require('lpke.plugins.ai.helpers.history_or_resume').open(beta)
vim.ui.select = original_select
picker = current_picker(2, 'Draft Prompts')
for index = 1, picker.manager:num_results() do
  if picker.manager:get_entry(index).value.path == draft_path then
    picker:set_selection(picker:get_row(index))
  end
end
flush()
eq(
  table
    .concat(api.nvim_buf_get_lines(picker.previewer.state.bufnr, 0, -1, false), '\n')
    :find('Saved draft quotation', 1, true) ~= nil,
  true,
  'Draft preview content'
)
actions.select_default(picker.prompt_bufnr)
flush()
local text =
  table.concat(api.nvim_buf_get_lines(beta.bufnr, 0, -1, false), '\n')
eq(
  text:find('Existing prompt', 1, true) ~= nil
    and text:find('Saved draft quotation\n> retain this', 1, true) ~= nil,
  true,
  'Draft appends and keeps quotation/current prompt'
)
drafts.open_picker(beta)
picker = current_picker(2)
mapping('dD')
eq(#drafts.list_current_cwd(), 1, 'Draft dD removes selected draft')
actions.close(picker.prompt_bufnr)
flush()

-- Previously saved summaries remain readable and attachable to a current chat.
api.nvim_set_current_buf(alpha.bufnr)
require('codecompanion.config').interactions.chat.keymaps['Browse Summaries'].callback(
  alpha
)
picker = current_picker(1, 'Saved Summaries')
eq(
  table.concat(
    api.nvim_buf_get_lines(picker.previewer.state.bufnr, 0, -1, false),
    '\n'
  ),
  'Fixture summary content',
  'Summary preview'
)
actions.select_default(picker.prompt_bufnr)
flush()
eq(
  vim.iter(alpha.messages):any(function(message)
    return message.content:find('Fixture summary content', 1, true) ~= nil
  end),
  true,
  'Summary selection attaches hidden context'
)
require('codecompanion.config').interactions.chat.keymaps['Browse Summaries'].callback(
  alpha
)
picker = current_picker(1, 'Saved Summaries')
vim.fn.confirm = function()
  return 1
end
mapping('d')
vim.fn.confirm = confirm
eq(history.get_summaries(), {}, 'Summary picker delete removes stored summary')

api.nvim_set_current_buf(alpha.bufnr)
open.open()
picker = current_picker(4)
picker:set_prompt('Beta', true)
picker = current_picker(1)
select_id(picker, beta.bufnr)
mapping('dD')
picker = current_picker(0)
eq(picker:_get_prompt(), 'Beta', 'Open-picker delete retains query')
eq(cc.buf_get_chat(beta.bufnr), nil, 'Open-picker dD closes selected live chat')
eq(history.load_chat('beta'), nil, 'Open-picker dD removes selected saved chat')
actions.close(picker.prompt_bufnr)
flush()

-- A saved search result also restores correctly after its live chat is closed.
local old_alpha = alpha.bufnr
alpha:close()
search.open({ default_text = 'Needle', initial_mode = 'normal' })
picker = current_picker(1)
actions.select_default(picker.prompt_bufnr)
flush()
alpha = cc.buf_get_chat(0)
eq(alpha.opts.save_id, 'alpha', 'Fresh search restore keeps saved ID')
eq(alpha.bufnr ~= old_alpha, true, 'Fresh search selection creates a new chat')
eq(alpha.adapter.type, 'acp', 'Fresh search restore uses saved ACP adapter')
eq(
  api.nvim_get_current_line(),
  'Needle in the first task',
  'Fresh restore jumps to exact matching row'
)

for _, entry in ipairs(cc.buf_get_chat()) do
  drafts.delete_for_buffer(entry.bufnr)
end
vim.cmd.cd(original_cwd)
vim.fn.delete(root, 'rf')
print(('PASS: %d saved/search/open/draft/summary picker checks'):format(checks))
