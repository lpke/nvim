-- Run after normal startup, scheduled as tests/nvim_0_12_dependency_validation.lua.
assert(vim.g.lazy_did_setup, 'Run this fixture after normal config startup')
local api = vim.api
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
vim.o.columns, vim.o.lines = 180, 60
local checks, errors, dates = 0, {}, 0
local actions = require('telescope.actions')
local state = require('telescope.actions.state')
local utils = require('telescope.utils')
local hl_range = utils.hl_range
local picker
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function wait(predicate, message)
  check(vim.wait(4000, predicate, 10), message)
end
local function git(...)
  local command = { 'git', '-C', root }
  vim.list_extend(command, { ... })
  local output = vim.fn.system(command)
  assert(vim.v.shell_error == 0, output)
end
local function close()
  if picker and api.nvim_buf_is_valid(picker.prompt_bufnr) then
    actions.close(picker.prompt_bufnr)
    vim.wait(50)
  end
  picker = nil
end
local function preview_ready()
  picker = state.get_current_picker(api.nvim_get_current_buf())
  return picker
    and picker.previewer
    and picker.previewer.state
    and picker.previewer.state.bufnr
    and api.nvim_buf_line_count(picker.previewer.state.bufnr) > 0
end
local function run()
  git('init', '-q')
  for index = 1, 6 do
    vim.fn.writefile(
      { 'local value = ' .. index, 'return value' },
      root .. '/file' .. index .. '.lua'
    )
  end
  git('add', '.')
  git(
    '-c',
    'user.name=Fixture',
    '-c',
    'user.email=fixture@localhost',
    'commit',
    '-qm',
    'Preview fixture'
  )
  git('branch', 'fixture-branch')

  utils.hl_range = function(...)
    local args = { ... }
    local ok, err = pcall(hl_range, ...)
    if not ok then
      errors[#errors + 1] = tostring(err)
      error(err)
    end
    if args[3] == 'TelescopeResultsSpecialComment' then
      dates = dates + 1
    end
  end
  require('telescope.builtin').git_branches({ cwd = root })
  wait(function()
    return preview_ready() and dates > 0
  end, 'Git branch dates are highlighted')
  check(#errors == 0, 'Git branch preview contains no swallowed range errors')
  close()

  require('telescope.builtin').find_files({
    cwd = root,
    find_command = { 'rg', '--files' },
  })
  wait(preview_ready, 'file preview ready')
  for cycle = 1, 3 do
    local before = picker.preview_win
    local off = vim.fn.maparg('<A-p>', 'i', false, true)
    check(
      type(off.callback) == 'function',
      'configured Alt-p mapping is available'
    )
    off.callback()
    wait(function()
      return require('telescope.state').get_status(picker.prompt_bufnr).layout.preview
        == nil
    end, 'preview toggles off')
    local on = vim.fn.maparg('<F2>p', 'n', false, true)
    check(
      type(on.callback) == 'function',
      'configured F2-p mapping is available'
    )
    on.callback()
    wait(function()
      return picker.preview_win and api.nvim_win_is_valid(picker.preview_win)
    end, 'preview toggles on')
    local after = picker.preview_win
    check(
      after ~= before and not api.nvim_win_is_valid(before),
      'preview uses a new window'
    )
    local ok, err =
      pcall(picker.set_selection, picker, picker:get_selection_row() + 1)
    check(ok, tostring(err))
    local selected = picker:get_selection().value
    local expected = vim.fn.readfile(root .. '/' .. selected)
    local loaded = vim.wait(4000, function()
      local actual =
        api.nvim_buf_get_lines(api.nvim_win_get_buf(after), 0, -1, false)
      -- This pinned previewer retains one terminal blank when reading a file.
      local padding = #actual == #expected
        or (#actual == #expected + 1 and actual[#actual] == '')
      return padding
        and vim.deep_equal(vim.list_slice(actual, 1, #expected), expected)
    end, 10)
    check(
      loaded,
      'uncached selection renders the expected file in the new preview'
    )
    check(
      picker.previewer.state.winid == after and vim.wo[after].wrap == false,
      'previewer tracks the current window and preserves wrapping'
    )
  end
  check(#errors == 0, 'all preview highlighting succeeded')
end
local ok, err = xpcall(run, debug.traceback)
utils.hl_range = hl_range
close()
vim.fn.delete(root, 'rf')
if not ok then
  print(err)
  vim.cmd('cquit 1')
end
print(('PASS Telescope previews: %d checks'):format(checks))
vim.cmd('qa!')
