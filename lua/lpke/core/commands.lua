local helpers = require('lpke.core.helpers')

Lpke_messages_win_open = false
Lpke_messages_win_id = nil
Lpke_messages_buf_id = nil

-- disabling shortcuts of :read to prevent accidental activation when typing :reg
vim.cmd('cabbrev r echo "shorthand for :read disabled"')
vim.cmd('cabbrev re echo "shorthand for :read disabled"')
vim.cmd('cabbrev rea echo "shorthand for :read disabled"')

-- stylua: ignore start
helpers.command_set_multi({
  { '', 'Bclean', Lpke_clean_buffers, { desc = 'Removes buffers that arent actively shown' } },

  -- terminal
  { '', 'TrashRestore', Lpke_trash_restore },
  { '*', 'T', Lpke_term }, -- arg: full
  { '*', 'Term', Lpke_term }, -- arg: full
  { '*', 'Terminal', Lpke_term }, -- arg: full
  { '*', 'R', Lpke_ranger }, -- arg: full
  { '*', 'Ranger', Lpke_ranger }, -- arg: full

  -- message window
  { '', 'M', Lpke_toggle_messages, { desc = 'Open :messages in a bottom split' } },
  { '', 'Mes', Lpke_toggle_messages, { desc = 'Open :messages in a bottom split' } },
  { '', 'Messages', Lpke_toggle_messages, { desc = 'Open :messages in a bottom split' } },

  -- printing
  { '?', 'P', function(cmd)
    if #cmd.fargs == 0 then
      print('PP: buf name | PC: cwd | PG: git root | PW: win details | P <lua>: Print(lua)')
    else
      Print(helpers.execute_as_lua(cmd.fargs[1]), 1)
    end
  end, { desc = 'Print help for `P` commands or call Print(<lua>)' } },
  { '', 'PP', function() print(helpers.get_buf_name()) end, { desc = 'Print the active buffer name' } },
  { '', 'PC', function() print(vim.fn.getcwd()) end, { desc = 'Print the current working directory' } },
  { '', 'PG', function() Lpke_git_root() end, { desc = 'Print the path of the git root of the current file' } },
  { '', 'PW', Lpke_active, { desc = 'Print details about the currently active tab/buffer/window' } },

  -- yanking
  { '', 'Y', function() print('YP/p: buf name | YD/d: cwd | YG/g: git root | YL/l: location | YT/t: tab ID | YB/b: buf ID | YW/w: win ID') end,
    { desc = 'Print help for `Y` commands' } },
  { '*', 'YP', function(cmd) Lpke_yank_buf_name(cmd, true) end }, -- arg: <register>
  { '*', 'Yp', function(cmd) Lpke_yank_buf_name(cmd, false) end }, -- arg: <register>
  { '*', 'YC', function(cmd) Lpke_yank_cwd(cmd, true) end }, -- arg: <register>
  { '*', 'Yc', function(cmd) Lpke_yank_cwd(cmd, false) end }, -- arg: <register>
  { '*', 'YG', function(cmd) Lpke_yank_git_root(cmd, true) end }, -- arg: <register>
  { '*', 'Yg', function(cmd) Lpke_yank_git_root(cmd, false) end }, -- arg: <register>
  { '*', 'YL', function(cmd) Lpke_yank_location(cmd, true) end }, -- arg: <register> ['blame']
  { '*', 'Yl', function(cmd) Lpke_yank_location(cmd, false) end }, -- arg: <register> ['blame']
  { '*', 'YT', function(cmd) Lpke_yank_tab_id(cmd, true) end }, -- arg: <register>
  { '*', 'Yt', function(cmd) Lpke_yank_tab_id(cmd, false) end }, -- arg: <register>
  { '*', 'YB', function(cmd) Lpke_yank_buf_id(cmd, true) end }, -- arg: <register>
  { '*', 'Yb', function(cmd) Lpke_yank_buf_id(cmd, false) end }, -- arg: <register>
  { '*', 'YW', function(cmd) Lpke_yank_win_id(cmd, true) end }, -- arg: <register>
  { '*', 'Yw', function(cmd) Lpke_yank_win_id(cmd, false) end }, -- arg: <register>

  -- changing directory (cd)
  { '', 'Cd', function() Lpke_cd_here('global') end, { desc = ':cd <current_dir>' } },
  { '', 'Cdr', function() Lpke_cd_root('global') end, { desc = ':cd <git_root_or_cwd>' } },
  { '', 'Tcd', function() Lpke_cd_here('tab') end, { desc = ':tcd <current_dir>' } },
  { '', 'Tcdr', function() Lpke_cd_root('tab') end, { desc = ':tcd <git_root_or_cwd>' } },
  { '', 'Lcd', function() Lpke_cd_here('window') end, { desc = ':lcd <current_dir>' } },
  { '', 'Lcdr', function() Lpke_cd_root('window') end, { desc = ':lcd <git_root_or_cwd>' } },
})
-- stylua: ignore end
