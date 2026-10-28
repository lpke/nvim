-- Run from the repository: nvim --headless -u NONE -i NONE -l tests/reference_jump.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.hidden = true
table.unpack = table.unpack or unpack
require('lpke.core.globals.git')

local helpers = require('lpke.core.helpers')
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
root = vim.uv.fs_realpath(root)
local project = root .. '/project'
local source = project .. '/docs/AGENTS.md'
local target = project .. '/docs/target.md'
local spaced = project .. '/docs/file (one) # %.md'
local checks = 0

local function equal(actual, expected, context)
  checks = checks + 1
  assert(
    vim.deep_equal(actual, expected),
    (context or '')
      .. '\nexpected: '
      .. vim.inspect(expected)
      .. '\nactual: '
      .. vim.inspect(actual)
  )
end

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile(lines or { 'one', 'two', 'three', 'four', 'five' }, path)
end

local function keys(value)
  vim.api.nvim_feedkeys(vim.keycode(value), 'xt', false)
end

local function edit(path)
  vim.cmd.edit({ args = { path }, magic = { file = false, bar = false } })
end

local opened_urls = {}
vim.ui.open = function(url)
  table.insert(opened_urls, url)
  return {}
end

local fallback_count = 0
helpers.keymap_set({
  'n',
  'gd',
  function()
    if not helpers.open_reference_under_cursor() then
      fallback_count = fallback_count + 1
    end
  end,
})

local function run()
  vim.fn.mkdir(project .. '/.git', 'p')
  vim.fn.mkdir(root .. '/cwd', 'p')
  vim.cmd.cd(root .. '/cwd')
  vim.env.LPKE_REFERENCE_FIXTURE = project
  write(target, { '# First', 'two', '## Some heading', 'four', 'five' })
  write(spaced)
  write(project .. '/src/app.lua')
  write(root .. '/cwd/fallback.lua')
  write(project .. '/docs/paren(one).md')
  write(project .. '/docs/literal:3')
  write(project .. '/docs/target.md:2')

  local skill = 'dot_agents/exact_skills/exact_chezmoi-skills/SKILL.md'
  write(project .. '/' .. skill)
  local example = '- For ai skill changes, read [chezmoi-skills]('
    .. skill
    .. ').'
  write(project .. '/AGENTS.md', { example })
  for _, needle in ipairs({ 'chezmoi-skills]', 'exact_skills', 'SKILL.md' }) do
    edit(project .. '/AGENTS.md')
    local cursor = { 1, example:find(needle, 1, true) - 1 }
    vim.api.nvim_win_set_cursor(0, cursor)
    keys('gd')
    equal(
      vim.api.nvim_buf_get_name(0),
      project .. '/' .. skill,
      'chezmoi example'
    )
    keys('<C-o>')
    equal(
      vim.api.nvim_buf_get_name(0),
      project .. '/AGENTS.md',
      'return to AGENTS.md'
    )
    equal(vim.api.nvim_win_get_cursor(0), cursor, 'restore source cursor')
  end

  -- Navigate through the public gd helper, including real back/forward jumps.
  local cases = {
    { '[label](target.md)', 'label', target },
    { '[label](target.md)', 'target', target },
    {
      '[label](./target.md "A title (with an unmatched parenthesis")',
      'label',
      target,
    },
    { '[label](paren(one).md)', 'label', project .. '/docs/paren(one).md' },
    { '[label](paren\\(one\\).md)', 'label', project .. '/docs/paren(one).md' },
    { '[label](<file (one) # %.md> "title")', 'label', spaced },
    { '[label](file%20%28one%29%20%23%20%25.md)', 'label', spaced },
    { '`file (one) # %.md`', 'one', spaced },
    { '"file (one) # %.md"', 'one', spaced },
    { "'file (one) # %.md'", 'one', spaced },
    { 'See (target.md).', 'target', target },
    { 'See <target.md>.', 'target', target },
    { 'require("target.md")', 'target', target },
    { '../src/app.lua', 'app', project .. '/src/app.lua' },
    { 'src/app.lua', 'app', project .. '/src/app.lua' },
    { 'fallback.lua', 'fallback', root .. '/cwd/fallback.lua' },
    { target, 'target', target },
    { '$LPKE_REFERENCE_FIXTURE/src/app.lua', 'app', project .. '/src/app.lua' },
    {
      '${LPKE_REFERENCE_FIXTURE}/src/app.lua',
      'FIXTURE',
      project .. '/src/app.lua',
    },
    { vim.uri_from_fname(spaced), 'file', spaced },
    { 'file://localhost' .. target, 'localhost', target },
    { 'target.md:4', 'target', target, { 4, 0 } },
    { 'target.md:4:3', 'target', target, { 4, 2 } },
    { 'target.md:999:999', 'target', target, { 5, 3 } },
    { 'target.md#L4', 'target', target, { 4, 0 } },
    { 'target.md#L4C3-L5', 'target', target, { 4, 2 } },
    { 'target.md#some-heading', 'target', target, { 3, 0 } },
    { 'literal:3', 'literal', project .. '/docs/literal:3' },
    { 'target.md:2', 'target', project .. '/docs/target.md:2' },
    { '[chosen][ My ID ]', 'chosen', target },
    { '[My ID][]', 'My ID', target },
    { '[My ID]', 'My ID', target },
    { '[My ID]: target.md "title"', 'My ID', target },
    { '[My ID]: target.md "title"', 'target', target },
    { '[multi][next-line]', 'multi', target },
    { '[one](missing.md) then [two](target.md)', 'two', target },
    { '~/ .missing', '.missing', false },
    { 'symbol_without_a_path', 'symbol', false },
    { '[missing](no-such-file.md)', 'missing', false },
    { 'file://remote-host' .. target, 'remote', false },
    { 'no-such-file.md', 'no-such', false },
  }
  local home_file = vim.fn.expand('~') .. '/.config/nvim/init.lua'
  if vim.fn.filereadable(home_file) == 1 then
    table.insert(cases, { '~/.config/nvim/init.lua', 'init', home_file })
  end
  local lines = {}
  for _, case in ipairs(cases) do
    table.insert(lines, case[1])
  end
  vim.list_extend(
    lines,
    { '', '[my id]: target.md', '[next-line]:', '  target.md' }
  )
  write(source, lines)
  for row, case in ipairs(cases) do
    edit(source)
    local cursor = { row, case[1]:find(case[2], 1, true) - 1 }
    vim.api.nvim_win_set_cursor(0, cursor)
    local fallback_before = fallback_count
    keys('gd')
    if case[3] then
      equal(vim.api.nvim_buf_get_name(0), case[3], case[1])
      equal(vim.api.nvim_win_get_cursor(0), case[4] or { 1, 0 }, case[1])
      equal(#vim.api.nvim_list_tabpages(), 1, 'same window')
      equal(fallback_count, fallback_before, 'no LSP fallback for file')
      keys('<C-o>')
      equal(vim.api.nvim_buf_get_name(0), source, 'jump back: ' .. case[1])
      equal(
        vim.api.nvim_win_get_cursor(0),
        cursor,
        'source position: ' .. case[1]
      )
      keys('<C-i>')
      equal(vim.api.nvim_buf_get_name(0), case[3], 'jump forward: ' .. case[1])
    else
      equal(vim.api.nvim_buf_get_name(0), source, 'unresolved path stays put')
      equal(fallback_count, fallback_before + 1, 'unresolved path uses LSP')
    end
  end

  local url_cases = {
    { "'https://example.com/path'", 'https', 'https://example.com/path' },
    {
      '[website](https://example.com/a_(b)?x=1 "title")',
      'website',
      'https://example.com/a_(b)?x=1',
    },
    { 'See https://example.com/a_(b).', 'https', 'https://example.com/a_(b)' },
    {
      '<http://localhost:3000/path#heading>',
      'localhost',
      'http://localhost:3000/path#heading',
    },
    { '[web][site]', 'web', 'https://example.com/path' },
  }
  for _, case in ipairs(url_cases) do
    vim.api.nvim_buf_set_lines(
      0,
      0,
      -1,
      false,
      { case[1], '[site]: https://example.com/path' }
    )
    equal(
      helpers.url_at(case[1], case[1]:find(case[2], 1, true)),
      case[3],
      'URL detection'
    )
    vim.api.nvim_win_set_cursor(0, { 1, case[1]:find(case[2], 1, true) - 1 })
    keys('gd')
    equal(opened_urls[#opened_urls], case[3], 'URL opened externally')
  end
  vim.bo.modified = false

  -- Same-file anchors must also enter the jumplist.
  write(
    project .. '/anchor.md',
    { '[jump](#some-heading)', 'two', '## Some heading' }
  )
  edit(project .. '/anchor.md')
  vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'unsaved text' })
  keys('gd')
  equal(vim.api.nvim_win_get_cursor(0), { 3, 0 }, 'same-file heading')
  equal(
    vim.api.nvim_buf_get_lines(0, 1, 2, false),
    { 'unsaved text' },
    'preserve unsaved edits'
  )
  keys('<C-o>')
  equal(vim.api.nvim_win_get_cursor(0), { 1, 0 }, 'same-file heading back')

  -- Chat retains its tab reuse and Ctrl-o return behavior with the shared parser.
  package.loaded['lpke.plugins.ai.helpers.img_clip'] = {
    dir_path = function()
      return root .. '/images'
    end,
  }
  local chat_jump = require('lpke.plugins.ai.helpers.reference_jump')
  vim.cmd.enew()
  vim.bo.buftype = 'nofile'
  vim.bo.bufhidden = 'hide'
  local chat_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '[file](<' .. spaced .. '>)' })
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  chat_jump.open_under_cursor()
  equal(vim.api.nvim_buf_get_name(0), spaced, 'chat opens a path with spaces')
  equal(#vim.api.nvim_list_tabpages(), 2, 'chat creates a tab')
  keys('G<C-o>')
  equal(#vim.api.nvim_list_tabpages(), 2, 'internal jump retains tab')
  keys('<C-o>')
  vim.wait(100, function()
    return #vim.api.nvim_list_tabpages() == 1
  end)
  equal(#vim.api.nvim_list_tabpages(), 1, 'return closes new chat file tab')
  equal(
    vim.api.nvim_get_current_buf(),
    chat_buf,
    'return to original chat window'
  )

  chat_jump.open_under_cursor()
  keys('<C-o>')
  vim.wait(100, function()
    return #vim.api.nvim_list_tabpages() == 1
  end)
  equal(
    #vim.api.nvim_list_tabpages(),
    1,
    'immediate chat return closes new tab'
  )
  equal(vim.api.nvim_get_current_buf(), chat_buf, 'immediate return to chat')

  write(root .. '/images/paste.png')
  vim.api.nvim_buf_set_lines(
    0,
    0,
    -1,
    false,
    { '[image](<' .. root .. '/images/paste.png>)' }
  )
  chat_jump.open_under_cursor()
  equal(
    opened_urls[#opened_urls],
    root .. '/images',
    'pasted image opens OS directory'
  )
  equal(#vim.api.nvim_list_tabpages(), 1, 'pasted image retains chat window')

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '[file](<' .. spaced .. '>)' })
  chat_jump.open_under_cursor()
  local file_win = vim.api.nvim_get_current_win()
  vim.cmd.tabprevious()
  chat_jump.open_under_cursor()
  equal(
    vim.api.nvim_get_current_win(),
    file_win,
    'chat reuses existing file window'
  )
  equal(#vim.api.nvim_list_tabpages(), 2, 'chat reuses existing file tab')
  vim.cmd.buffer(chat_buf)
  vim.wait(10)
  equal(#vim.api.nvim_list_tabpages(), 2, 'manual buffer switch retains tab')
  vim.cmd.tabclose()

  print('Reference navigation: ' .. checks .. ' checks passed')
end

local ok, err = xpcall(run, debug.traceback)
vim.fn.delete(root, 'rf')
if not ok then
  error(err)
end
