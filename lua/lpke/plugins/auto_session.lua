local function config()
  local auto_session = require('auto-session')
  local session_lens = require('auto-session.session-lens')
  local helpers = require('lpke.core.helpers')

  -- stylua: ignore start
  -- keymaps
  helpers.keymap_set_multi({
    {'n', '<BS>n', session_lens.search_session, { desc = 'Open session picker in Telescope' }},
  })
  -- stylua: ignore end

  auto_session.setup({
    enabled = true,
    suppressed_dirs = { '/', '~/', '~/Downloads' },
    root_dir = vim.fn.stdpath('data') .. '/sessions/',
    auto_restore_last_session = false, -- load last session for cwd if doesnt exist
    auto_save = true,
    auto_restore = true,
    git_use_branch_name = false, -- differentiate by git branch name (false because worktrees are better)
    bypass_save_filetypes = { '' }, -- dont auto-save when only buffer open is one of these file types
    log_level = 'error',
    cwd_change_handling = true, -- when changing cwd, save current session and restore incoming session

    -- hooks
    post_cwd_changed_cmds = {
      function()
        require('lualine').refresh()
      end,
    },

    session_lens = {
      load_on_setup = true,
      -- telescope picker options
      theme_conf = {
        initial_mode = 'normal',
        sorting_strategy = 'ascending',
        winblend = 0,
        border = true,
        previewer = false,
        layout_strategy = 'vertical',
        layout_config = {
          width = 140,
          height = 26,
        },
      },
    },
  })

  -- command abbreviations
  vim.cmd('cabbrev SS SessionSave')
  vim.cmd('cabbrev SR SessionRestore')
  vim.cmd('cabbrev SD SessionDelete')
  vim.cmd('cabbrev Ss Autosession search')
  vim.cmd('cabbrev Sd Autosession delete')
end

return {
  'rmagatti/auto-session',
  lazy = false,
  priority = 900,
  config = config,
}
