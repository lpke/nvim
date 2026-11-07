-- Test-only entrypoint. Execute the real config and review plugin configuration,
-- while replacing the broad Lazy import with a closed set of installed copies.
local root = assert(vim.env.LPKE_REVIEW_HARNESS, 'private harness required')
local config = root .. '/config/nvim'
local plugins = root .. '/data/nvim/lazy/'
vim.opt.runtimepath = { config, vim.env.VIMRUNTIME }
vim.opt.packpath = {}
vim.opt.runtimepath:append(config .. '/after')
vim.g.loaded_python3_provider = 0
vim.g.loaded_python_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_netrwPlugin = 1

local violations = {}
local function deny(reason)
  violations[#violations + 1] = reason
  error('review harness denied ' .. reason)
end
local clipboard = { ['+'] = { {}, 'v' }, ['*'] = { {}, 'v' } }
local function copy(register)
  return function(lines, kind) clipboard[register] = { vim.deepcopy(lines), kind } end
end
local function paste(register)
  return function() return vim.deepcopy(clipboard[register]) end
end
local private_clipboard = {
  name = 'private-review', cache_enabled = 0,
  copy = { ['+'] = copy('+'), ['*'] = copy('*') },
  paste = { ['+'] = paste('+'), ['*'] = paste('*') },
}
vim.g.clipboard = private_clipboard
package.preload['vim.ui.clipboard.osc52'] = function() deny('OSC52 clipboard') end

-- Guard the real subprocess entrypoints, including libuv jobs used by Diffview.
-- Unexpected startup activity fails the probe even if a plugin catches the error.
local readonly = {
  ['--version'] = true, version = true, ['rev-parse'] = true,
  ['rev-list'] = true, ['symbolic-ref'] = true, ['ls-files'] = true,
  ['ls-tree'] = true, ['cat-file'] = true, show = true, log = true,
  grep = true, diff = true, ['diff-tree'] = true, ['diff-files'] = true,
  ['diff-index'] = true, status = true, ['merge-base'] = true,
  ['for-each-ref'] = true, ['check-attr'] = true, ['check-ignore'] = true,
  ['--exec-path'] = true,
}
local function command(program, args, cwd)
  if type(program) ~= 'string' or vim.fn.fnamemodify(program, ':t') ~= 'git' then
    deny('process ' .. tostring(program))
  end
  local i = 1
  while args[i] do
    local arg = args[i]
    if arg == '-C' or arg == '-c' or arg == '--git-dir' or arg == '--work-tree' then
      if arg == '-C' then cwd = args[i + 1] end
      i = i + 2
    elseif arg:match('^%-') and not readonly[arg] then
      -- Only global flags emitted by the production adapters/plugin.
      if arg ~= '--no-optional-locks' and arg ~= '--literal-pathspecs'
        and arg ~= '--no-pager' and arg ~= '-P' then deny('git global option ' .. arg) end
      i = i + 1
    else
      local config_read = arg == 'config' and args[i + 1] == 'status.showUntrackedFiles'
        and args[i + 2] == nil
      local hash_read = arg == 'hash-object' and args[i + 1] == '-t'
        and args[i + 2] == 'tree' and args[i + 3] == '--stdin' and args[i + 4] == nil
      local mutation = (arg == 'add' or arg == 'reset')
        and vim.env.LPKE_REVIEW_MUTATION_REPO
        and vim.uv.fs_realpath(cwd or vim.uv.cwd()) == vim.env.LPKE_REVIEW_MUTATION_REPO
        and vim.tbl_contains(args, '--')
      if not readonly[arg] and not config_read and not hash_read and not mutation then
        deny('git command ' .. arg)
      end
      break
    end
  end
end
local spawn = vim.uv.spawn
vim.uv.spawn = function(program, opts, ...)
  command(program, opts.args or {}, opts.cwd)
  return spawn(program, opts, ...)
end
local system = vim.system
vim.system = function(argv, opts, ...)
  command(argv[1], vim.list_slice(argv, 2), opts and opts.cwd)
  return system(argv, opts, ...)
end
for _, name in ipairs({ 'system', 'systemlist', 'jobstart', 'termopen' }) do
  local original = vim.fn[name]
  vim.fn[name] = function(argv, opts, ...)
    if type(argv) ~= 'table' then deny(name .. ' shell') end
    command(argv[1], vim.list_slice(argv, 2), type(opts) == 'table' and opts.cwd or nil)
    return original(argv, opts, ...)
  end
end
os.execute = function() deny('os.execute') end
io.popen = function() deny('io.popen') end
for _, name in ipairs({ 'tcp_connect', 'tcp_bind', 'udp_send', 'udp_connect', 'getaddrinfo', 'new_tcp', 'new_udp' }) do
  vim.uv[name] = function() deny('network ' .. name) end
end

-- Only these plugin configs are relevant to review behavior. No Mason, Harpoon,
-- AI/provider, personal local extensions or package installation is imported.
package.preload['lpke.lazy'] = function()
  vim.opt.runtimepath:prepend(plugins .. 'lazy.nvim')
  local function spec(module, name)
    local value = require(module)
    value.dir = plugins .. name
    return value
  end
  local review = spec('lpke.plugins.git.diffview', 'diffview.nvim')
  local theme = spec('lpke.plugins.rose_pine', 'rose-pine')
  require('lazy').setup({
    theme, review,
    { dir = plugins .. 'plenary.nvim', lazy = false },
    { dir = plugins .. 'nvim-web-devicons', lazy = false },
    { dir = plugins .. 'lualine.nvim', lazy = false },
    { dir = plugins .. 'auto-session', lazy = false, config = function()
      -- Real session plugin, disabled before it installs any session activity.
      require('auto-session').setup({ enabled = false, auto_save = false,
        auto_restore = false, session_lens = { load_on_setup = false } })
    end },
  }, {
    root = plugins, lockfile = config .. '/lazy-lock.json',
    install = { missing = false }, checker = { enabled = false },
    change_detection = { enabled = false }, readme = { enabled = false },
    rocks = { enabled = false }, performance = { rtp = { reset = false } },
  })
  return true
end

-- Turn accidental reintroduction of unrelated startup into a visible failure.
for _, module in ipairs({ 'mason', 'mason-registry', 'mason-lspconfig',
  'mason-tool-installer', 'harpoon', 'codecompanion', 'copilot' }) do
  package.preload[module] = function() deny('unrelated module ' .. module) end
end
function Lpke_review_harness_check()
  assert(#violations == 0, table.concat(violations, '\n'))
  for _, kind in ipairs({ 'config', 'data', 'cache', 'state' }) do
    assert(vim.fn.stdpath(kind):sub(1, #root + 1) == root .. '/', 'escaped ' .. kind)
  end
  assert(vim.g.clipboard.name == 'private-review', 'real clipboard provider')
  assert(require('auto-session.config').enabled == false, 'sessions enabled')
  for _, name in ipairs({ 'mason', 'mason-registry', 'harpoon', 'codecompanion', 'copilot' }) do
    assert(not package.loaded[name], 'unrelated plugin loaded: ' .. name)
  end
end
-- Preserve production core, options, globals, tabline, autocmds and plugin adapter.
dofile(config .. '/init.lua')
-- The production options can select OSC52/WSL based on host environment. Keep
-- the provider private even when exercising a source copy from another OS.
vim.g.clipboard = private_clipboard
