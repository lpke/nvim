-- ensure lazy is installed, then initialise
local lazy_path = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazy_path) then
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', -- latest stable release
    lazy_path,
  })
end
vim.opt.rtp:prepend(lazy_path)

-- where lazy should look for plugins
local lazy_plugins = {
  { import = 'lpke.plugins' },
  { import = 'lpke.plugins.lsp' },
}

-- lazy config options
local lazy_options = {
  checker = {
    enabled = true,
    notify = false,
  },
  change_detection = {
    notify = false,
  },
  ui = {
    border = 'none',
    pills = true,
    icons = {
      cmd = '⌘ ',
      config = '☼',
      event = '▣',
      ft = '◆ ',
      init = '☇ ',
      import = '↘',
      keys = '₸ ',
      lazy = 'ℓ  ',
      loaded = '●',
      not_loaded = '○',
      plugin = '⏻',
      runtime = '◌',
      require = '☛',
      source = '☑',
      start = '▶',
      task = '✔ ',
      list = {
        '●',
        '-',
        '↳',
        '-',
        '↳',
        '-',
        '↳',
        '-',
        '↳',
        '-',
        '↳',
        '-',
        '↳',
        '-',
        '↳',
      },
    },
  },
}

-- keymaps
require('lpke.core.helpers').keymap_set_multi({
  {'nC', '<BS>il', 'Lazy', { desc = 'Open lazy.nvim GUI' }},
})

-- setup lazy
require('lazy').setup(lazy_plugins, lazy_options)
