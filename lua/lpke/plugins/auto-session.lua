local function config()
  local auto_session = require('auto-session')
  local session_lens = require('auto-session.session-lens')
  local helpers = require('lpke.core.helpers')

  -- keymaps
  helpers.keymap_set_multi({
    {
      'n',
      '<BS>n',
      session_lens.search_session,
      { desc = 'Open session picker in Telescope' },
    },
  })

  auto_session.setup({
    auto_session_enabled = true,
    auto_session_suppress_dirs = { '/', '~/', '~/Downloads' },
    auto_session_root_dir = vim.fn.stdpath('data') .. '/sessions/',
    auto_session_enable_last_session = false, -- load last session for cwd if doesnt exist
    auto_save_enabled = true,
    auto_restore_enabled = true,
    auto_session_use_git_branch = false, -- differentiate by git branch name (false because worktrees are better)
    bypass_session_save_file_types = { '' }, -- dont auto-save when only buffer open is one of these file types
    log_level = 'error',
    cwd_change_handling = {
      restore_upcoming_session = false, -- enabling this causes me errors when swapping with telescope
      post_cwd_changed_hook = function()
        require('lualine').refresh()
      end,
    },
    session_lens = {
      load_on_setup = true,
      buftypes_to_ignore = {}, -- list of buffer types that should not be deleted from current session

      -- telescope picker options
      theme = 'vertical',
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
