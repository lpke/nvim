local function config()
  local harpoon = require('harpoon')
  local harpoon_ui = require('harpoon.ui')
  local harpoon_mark = require('harpoon.mark')
  local harpoon_term = require('harpoon.term')
  local harpoon_cmd_ui = require('harpoon.cmd-ui')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  helpers.keymap_set_multi({
    { 'n', '<CR>', harpoon_ui.toggle_quick_menu, { desc = 'Harpoon: Toggle quick menu' } },
    { 'n', '<F2>a', harpoon_mark.add_file, { desc = 'Harpoon: Mark file' } },
    { 'n', '<F2>x', harpoon_mark.rm_file, { desc = 'Harpoon: Remove current file' } },
    { 'n', '<F2>1', function() harpoon_ui.nav_file(1) end, { desc = 'Harpoon: Go to file 1' } },
    { 'n', '<F2>2', function() harpoon_ui.nav_file(2) end, { desc = 'Harpoon: Go to file 2' } },
    { 'n', '<F2>3', function() harpoon_ui.nav_file(3) end, { desc = 'Harpoon: Go to file 3' } },
    { 'n', '<F2>4', function() harpoon_ui.nav_file(4) end, { desc = 'Harpoon: Go to file 4' } },
    { 'n', '<F2>5', function() harpoon_ui.nav_file(5) end, { desc = 'Harpoon: Go to file 5' } },
    { 'n', '<F2>6', function() harpoon_ui.nav_file(6) end, { desc = 'Harpoon: Go to file 6' } },
    { 'n', '<F2>7', function() harpoon_ui.nav_file(7) end, { desc = 'Harpoon: Go to file 7' } },
    { 'n', '<F2>8', function() harpoon_ui.nav_file(8) end, { desc = 'Harpoon: Go to file 8' } },
    { 'n', '<F2>9', function() harpoon_ui.nav_file(9) end, { desc = 'Harpoon: Go to file 9' } },
    { 'n', '<F2>a', harpoon_mark.add_file, { desc = 'Harpoon: Mark file' } },

    -- adding <BS> version in case I'm confined to a normal keyboard
    { 'n', '<BS>a', harpoon_mark.add_file, { desc = 'Harpoon: Mark file' } },
    { 'n', '<BS>x', harpoon_mark.rm_file, { desc = 'Harpoon: Remove current file' } },
    { 'n', '<BS>1', function() harpoon_ui.nav_file(1) end, { desc = 'Harpoon: Go to file 1' } },
    { 'n', '<BS>2', function() harpoon_ui.nav_file(2) end, { desc = 'Harpoon: Go to file 2' } },
    { 'n', '<BS>3', function() harpoon_ui.nav_file(3) end, { desc = 'Harpoon: Go to file 3' } },
    { 'n', '<BS>4', function() harpoon_ui.nav_file(4) end, { desc = 'Harpoon: Go to file 4' } },
    { 'n', '<BS>5', function() harpoon_ui.nav_file(5) end, { desc = 'Harpoon: Go to file 5' } },
    { 'n', '<BS>6', function() harpoon_ui.nav_file(6) end, { desc = 'Harpoon: Go to file 6' } },
    { 'n', '<BS>7', function() harpoon_ui.nav_file(7) end, { desc = 'Harpoon: Go to file 7' } },
    { 'n', '<BS>8', function() harpoon_ui.nav_file(8) end, { desc = 'Harpoon: Go to file 8' } },
    { 'n', '<BS>9', function() harpoon_ui.nav_file(9) end, { desc = 'Harpoon: Go to file 9' } },
  })

  harpoon.setup({
    -- sets the marks upon calling `toggle` on the ui, instead of require `:w`
    save_on_toggle = false,

    -- saves the harpoon file upon every change - disabling not recommended
    save_on_change = true,

    -- sets harpoon to run the command immediately as it's passed to the terminal when calling `sendCommand`
    enter_on_sendcmd = false,

    -- closes any tmux windows harpoon that harpoon creates when you close Neovim
    tmux_autoclose_windows = false,

    -- filetypes that you want to prevent from adding to the harpoon list menu
    excluded_filetypes = { 'harpoon' },

    -- set marks specific to each git branch inside git repository
    mark_branch = false,

    -- enable tabline with harpoon marks
    tabline = false,
    tabline_prefix = '   ',
    tabline_suffix = '   ',
  })
end

return {
  'ThePrimeagen/harpoon',
  config = config,
}