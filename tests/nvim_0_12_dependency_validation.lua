-- Run after normal startup: run-nvim --headless -i NONE -c "lua vim.schedule(function() dofile('tests/nvim_0_12_dependency_validation.lua') end)"
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.columns, vim.o.lines = 180, 60
vim.o.loadplugins = true
local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local deprecations = {}
local deprecate, native_validate = vim.deprecate, vim.validate
vim.deprecate = function(name, ...)
  deprecations[#deprecations + 1] = debug.traceback(name, 2)
  return deprecate(name, ...)
end

-- Exercise the actual bootstrap and Lazy dependency order, including after/plugin.
assert(vim.g.lazy_did_setup, 'Run this fixture after normal Neovim startup')
require('lazy').load({
  plugins = { 'telescope.nvim', 'diffview.nvim', 'dressing.nvim', 'nvim-cmp' },
})
vim.wait(100)
check(vim.validate == native_validate, 'native validator was not replaced')
local function buffer(ft, lines)
  vim.cmd('enew!')
  vim.bo.filetype = ft
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines or { '' })
  return vim.api.nvim_get_current_buf()
end

-- Both Plenary semaphore APIs retain their permit queues and metatables.
print('dependency validation: Plenary semaphore APIs')
for _, name in ipairs({ 'plenary.async.control', 'plenary.async_lib.util' }) do
  local class = require(name).Semaphore
  local semaphore = class.new(1)
  check(getmetatable(semaphore) == class, name .. ' metatable')
  check(class.new(0.5).permits == 0.5, name .. ' positive fractions retained')
  check(not pcall(class.new, 0), name .. ' rejects zero')
  check(not pcall(class.new, -1), name .. ' rejects negative permits')
  check(not pcall(class.new, 'one'), name .. ' rejects invalid type')
  local first, second
  local function acquire(callback)
    if name == 'plenary.async.control' then
      semaphore:acquire(callback)
    else
      semaphore:acquire()(callback)
    end
  end
  acquire(function(permit)
    first = permit
  end)
  acquire(function(permit)
    second = permit
  end)
  check(first ~= nil and second == nil, name .. ' waits for a permit')
  check(
    semaphore.permits == 0 and #semaphore.handles == 1,
    name .. ' waiting queue'
  )
  first:forget()
  check(second ~= nil and #semaphore.handles == 0, name .. ' releases waiter')
  second:forget()
  check(semaphore.permits == 1, name .. ' restores permit')
end

-- Buffer completion indexes actual edits and still rejects invalid options.
print('dependency validation: buffer completion')
local word_buf = buffer('text', { 'alphaword betaword alphaword', 'gammaword' })
local source = require('cmp_buffer')
local params = {
  option = { indexing_interval = 1 },
  context = { cursor_before_line = 'alp' },
  offset = 1,
}
local result
source:complete(params, function(items)
  result = items
end)
print('dependency validation: buffer source completion requested')
check(
  vim.wait(2000, function()
    return result ~= nil
  end),
  'buffer completion indexing'
)
check(
  type(result.isIncomplete) == 'boolean',
  'buffer completion indexing status'
)
local function contains(items, label)
  for _, item in ipairs(items) do
    if item.label == label then
      return item
    end
  end
end
check(contains(result.items, 'alphaword'), 'buffer completion word')
local occurrences = 0
for _, item in ipairs(result.items) do
  if item.label == 'alphaword' then
    occurrences = occurrences + 1
  end
end
check(occurrences == 1, 'buffer completion deduplicates words')
print('dependency validation: buffer source indexed')
vim.api.nvim_buf_set_lines(word_buf, 0, -1, false, { 'deltaword' })
result = nil
source:complete(params, function(items)
  result = items
end)
check(
  vim.wait(2000, function()
    return result ~= nil and contains(result.items, 'deltaword') ~= nil
  end),
  'buffer completion follows edits'
)
print('dependency validation: buffer source edit indexed')
check(
  not pcall(
    source.get_keyword_pattern,
    source,
    { option = { keyword_length = 'bad' } }
  ),
  'buffer option validation retained'
)
vim.api.nvim_buf_delete(word_buf, { force = true })
print('dependency validation: buffer source closed')

-- Real LuaSnip entries pass completion options, visibility filters and expansion.
print('dependency validation: LuaSnip completion')
local ls = require('luasnip')
local snippet_source = require('cmp_luasnip').new()
local snippet_buf = buffer('lpke_dependency_fixture', { '' })
ls.add_snippets('lpke_dependency_fixture', {
  ls.snippet(
    { trig = 'fixture_visible', name = 'Visible fixture' },
    { ls.text_node('expanded fixture') }
  ),
  ls.snippet({
    trig = 'fixture_hidden',
    show_condition = function()
      return false
    end,
  }, { ls.text_node('hidden fixture') }),
}, { key = 'lpke_dependency_validation' })
snippet_source.clear_cache()
local items
snippet_source:complete(
  { option = {}, context = { cursor_before_line = 'fixture_' } },
  function(values)
    items = values
  end
)
local visible = contains(items, 'fixture_visible')
check(visible ~= nil, 'LuaSnip completion entry')
check(not contains(items, 'fixture_hidden'), 'LuaSnip visibility filter')
snippet_source:complete({
  option = { use_show_condition = false },
  context = { cursor_before_line = 'fixture_' },
}, function(values)
  items = values
end)
check(
  contains(items, 'fixture_hidden'),
  'LuaSnip explicit show condition override'
)
check(
  not pcall(
    snippet_source.complete,
    snippet_source,
    { option = { show_autosnippets = 'bad' }, context = {} },
    function() end
  ),
  'LuaSnip option validation retained'
)
local resolved
snippet_source:resolve(visible, function(item)
  resolved = item
end)
check(
  resolved.documentation.value:find('Visible fixture', 1, true),
  'LuaSnip documentation'
)
vim.api.nvim_buf_set_lines(snippet_buf, 0, -1, false, { visible.word })
vim.o.virtualedit = 'onemore'
vim.api.nvim_win_set_cursor(0, { 1, #visible.word })
local expanded = false
snippet_source:execute(visible, function()
  expanded = true
end)
check(
  expanded and vim.api.nvim_get_current_line() == 'expanded fixture',
  'LuaSnip actual expansion'
)
ls.unlink_current()
vim.o.virtualedit = ''

-- Dressing input and numbered selection use the configured production backends.
print('dependency validation: Dressing inputs and selections')
local confirmed, input_done
vim.ui.input({ prompt = 'Fixture input', default = 'before' }, function(value)
  confirmed, input_done = value, true
end)
check(
  vim.wait(1000, function()
    return vim.bo.filetype == 'DressingInput'
  end),
  'Dressing input opened'
)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'after' })
require('dressing.input').confirm()
check(vim.wait(1000, function()
  return input_done == true
end) and confirmed == 'after', 'Dressing input confirm')
input_done = false
vim.ui.input({ prompt = 'Cancel input' }, function(value)
  confirmed, input_done = value, true
end)
check(
  vim.wait(1000, function()
    return vim.bo.filetype == 'DressingInput'
  end),
  'Dressing second input opened'
)
require('dressing.input').close()
check(vim.wait(1000, function()
  return input_done == true
end) and confirmed == nil, 'Dressing input cancel')
local chosen, chosen_index, selected
vim.ui.select(
  { 'first', 'second' },
  { prompt = 'Fixture selection', kind = 'codecompanion.nvim' },
  function(item, index)
    chosen, chosen_index, selected = item, index, true
  end
)
check(
  vim.wait(1000, function()
    return vim.bo.filetype == 'DressingSelect'
  end),
  'Dressing builtin select opened'
)
check(
  vim.api.nvim_get_current_line():find('[1]', 1, true),
  'Dressing numbered items retained'
)
local number_marks = vim.api.nvim_buf_get_extmarks(
  0,
  vim.api.nvim_get_namespaces().DressingSelect,
  0,
  -1,
  { details = true }
)
check(
  #number_marks == 2
    and number_marks[1][4].hl_group == 'DressingSelectIdx'
    and number_marks[1][4].end_col == 4,
  'Dressing numbered highlights retained'
)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
require('dressing.select.builtin').choose()
check(vim.wait(1000, function()
  return selected == true
end) and chosen == 'second' and chosen_index == 2, 'Dressing selection confirm')
selected = false
vim.ui.select(
  { 'first' },
  { prompt = 'Cancel selection', kind = 'codecompanion.nvim' },
  function(item, index)
    chosen, chosen_index, selected = item, index, true
  end
)
check(
  vim.wait(1000, function()
    return vim.bo.filetype == 'DressingSelect'
  end),
  'Dressing second select opened'
)
require('dressing.select.builtin').cancel()
check(vim.wait(1000, function()
  return selected == true
end) and chosen == nil and chosen_index == nil, 'Dressing selection cancel')

-- Real Git history covers initial, renamed, binary, merge and empty commits.
print('dependency validation: Git fixtures')
local Panel = require('diffview.ui.panel').Panel
local split_config = { position = 'bottom', win_opts = { wrap = true } }
local split_panel = Panel({ config = split_config })
local split = split_panel:get_config()
check(
  split.type == 'split' and split.relative == 'editor' and split.win == 0,
  'Diffview split defaults'
)
check(split_panel.state.form == 'row', 'Diffview split orientation')
check(
  split.win_opts ~= split_config.win_opts and split.win_opts.wrap,
  'Diffview config cloned'
)
local produced = 0
local float_panel = Panel({
  config = function()
    produced = produced + 1
    return {
      type = 'float',
      width = 40,
      height = 6,
      relative = 'cursor',
      anchor = 'SW',
      border = { '+', '-' },
    }
  end,
})
local floating = float_panel:get_config()
check(
  produced == 1 and floating.style == 'minimal' and floating.zindex == 50,
  'Diffview callable float defaults'
)
check(
  floating.row == 0 and floating.col == 0 and floating.win == nil,
  'Diffview optional float fields'
)
check(not pcall(function()
  Panel({ config = { position = 'invalid' } }):get_config()
end), 'Diffview invalid split position rejected')
check(not pcall(function()
  Panel({
    config = { type = 'float', width = 40, height = 6, border = { '+' } },
  }):get_config()
end), 'Diffview short border rejected')
local original_cwd = vim.fn.getcwd()
local repo = vim.fn.tempname()
vim.fn.mkdir(repo, 'p')
local function git(...)
  local command = {
    'git',
    '-C',
    repo,
    '-c',
    'user.name=Neovim Fixture',
    '-c',
    'user.email=fixture@example.invalid',
  }
  vim.list_extend(command, { ... })
  local result = vim.system(command, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout or '')
end
git('init', '-b', 'main', '--quiet')
vim.fn.writefile(
  { 'first line', 'second line', 'third line' },
  repo .. '/original.txt'
)
git('add', '.')
git('commit', '--quiet', '-m', 'initial fixture')
local initial_hash = git('rev-parse', 'HEAD')
git('mv', 'original.txt', 'renamed.txt')
local binary = assert(io.open(repo .. '/binary.bin', 'wb'))
binary:write('binary\0fixture')
binary:close()
git('add', '.')
git('commit', '--quiet', '-m', 'rename and binary fixture')
local renamed_hash = git('rev-parse', 'HEAD')
git('checkout', '--quiet', '-b', 'side')
vim.fn.writefile({ 'side fixture' }, repo .. '/side.txt')
git('add', '.')
git('commit', '--quiet', '-m', 'side fixture')
git('checkout', '--quiet', 'main')
vim.fn.writefile(
  { 'first line changed', 'second line', 'third line' },
  repo .. '/renamed.txt'
)
git('commit', '--quiet', '-am', 'main fixture')
git('merge', '--quiet', '--no-edit', 'side')
git('commit', '--quiet', '--allow-empty', '-m', 'empty fixture')
vim.fn.writefile(
  { 'working change', 'second line', 'third line' },
  repo .. '/renamed.txt'
)
vim.cmd('enew!')
vim.cmd.cd(repo)
vim.cmd.DiffviewOpen()
print('dependency validation: Diffview working tree')
local lib = require('diffview.lib')
local diff
check(
  vim.wait(5000, function()
    diff = lib.get_current_view()
    return diff and diff.ready and #diff.files.working > 0
  end),
  'Diffview working diff opened'
)
check(diff.panel:is_open(), 'Diffview file panel opened')
check(diff.files.working[1].path == 'renamed.txt', 'Diffview changed path')
check(
  vim.wait(5000, function()
    return diff.cur_entry ~= nil and diff.cur_entry.opened == true
  end),
  'Diffview revision buffers finished loading'
)
vim.cmd.DiffviewClose()

local function history(command)
  vim.cmd(command)
  local view
  check(
    vim.wait(5000, function()
      view = lib.get_current_view()
      return view
        and view.panel
        and view.panel.entries
        and #view.panel.entries > 0
        and not view.panel.updating
        and view.cur_entry ~= nil
        and view.cur_entry.opened == true
    end),
    command .. ' loaded'
  )
  check(view.panel:is_open(), command .. ' panel opened')
  return view
end
local full_history = history('DiffviewFileHistory')
print('dependency validation: Diffview branch history')
local entry_by_subject = {}
for _, entry in ipairs(full_history.panel.entries) do
  entry_by_subject[entry.commit.subject] = entry
end
check(entry_by_subject['initial fixture'] ~= nil, 'Git initial commit history')
local renamed_entry = assert(entry_by_subject['rename and binary fixture'])
local saw_rename, saw_binary = false, false
for _, file in ipairs(renamed_entry.files) do
  saw_rename = saw_rename
    or (file.path == 'renamed.txt' and file.oldpath == 'original.txt')
  saw_binary = saw_binary or (file.path == 'binary.bin' and file.stats == nil)
end
check(saw_rename, 'Git rename history metadata')
check(saw_binary, 'Git binary history metadata')
check(
  entry_by_subject['side fixture'] ~= nil
    and entry_by_subject['main fixture'] ~= nil,
  'Git merged branch history'
)

-- Explicitly exercise the retry producer, which shares the private validator.
local state = {
  single_file = false,
  path_args = {},
  log_options = { diff_merges = 'combined' },
}
local err, retry_data = require('diffview.async').await(
  full_history.adapter:fh_retry_commit(renamed_hash, state, { retry_count = 1 })
)
check(err == nil and retry_data.valid, 'Git history retry data')
check(
  retry_data.right_hash == renamed_hash and retry_data.left_hash == initial_hash,
  'Git retry commit parents'
)
check(
  #retry_data.namestat == #retry_data.numstat and #retry_data.numstat == 2,
  'Git retry stat balance'
)
local failure = require('diffview.async').await(
  full_history.adapter:fh_retry_commit(
    'missing-fixture-revision',
    state,
    { retry_count = 1 }
  )
)
check(
  failure and failure.name == 'job_fail',
  'Git history retry failure retained'
)
vim.cmd.DiffviewClose()
local file_history = history('DiffviewFileHistory renamed.txt')
check(file_history.panel.single_file, 'single-file history mode')
check(#file_history.panel.entries >= 2, 'single-file history follows rename')
vim.cmd.DiffviewClose()
history('DiffviewFileHistory -L1,2:renamed.txt')
vim.cmd.DiffviewClose()
vim.cmd.cd(original_cwd)
vim.fn.delete(repo, 'rf')

check(
  vim.validate == native_validate,
  'native validator retained after every workflow'
)
check(
  #deprecations == 0,
  'deprecated calls:\n' .. table.concat(deprecations, '\n')
)
vim.deprecate = deprecate
print(('nvim_0_12_dependency_validation: %d checks passed'):format(checks))
vim.cmd('qa!')
