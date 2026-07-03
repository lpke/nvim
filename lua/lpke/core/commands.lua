local helpers = require('lpke.core.helpers')
local custom_help = require('lpke.core.help')

Lpke_messages_win_open = false
Lpke_messages_win_id = nil
Lpke_messages_buf_id = nil

-- disabling shortcuts of :read to prevent accidental activation when typing :reg
vim.cmd('cabbrev r echo "shorthand for :read disabled"')
vim.cmd('cabbrev re echo "shorthand for :read disabled"')
vim.cmd('cabbrev rea echo "shorthand for :read disabled"')

local function codex_usage()
  local script = vim.fn.expand('~/.local/bin/cu')

  if vim.fn.executable(script) ~= 1 then
    vim.api.nvim_echo({ { script .. ' is not executable', 'ErrorMsg' } }, true, {})
    return
  end

  local function echo_output(output, code)
    vim.schedule(function()
      local hl = code == 0 and 'None' or 'ErrorMsg'
      vim.api.nvim_echo({ { output, hl } }, true, {})
    end)
  end

  if vim.system then
    vim.system({ script }, { text = true }, function(result)
      echo_output(vim.trim(result.stdout ~= '' and result.stdout or result.stderr), result.code)
    end)
    return
  end

  local output = {}
  vim.fn.jobstart({ script }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      vim.list_extend(output, vim.tbl_filter(function(line) return line ~= '' end, data))
    end,
    on_stderr = function(_, data)
      vim.list_extend(output, vim.tbl_filter(function(line) return line ~= '' end, data))
    end,
    on_exit = function(_, code)
      echo_output(table.concat(output, '\n'), code)
    end,
  })
end

local function open_explorer_here()
  local dir = nil

  if vim.bo.filetype == 'oil' then
    local ok, oil = pcall(require, 'oil')
    if ok then
      dir = oil.get_current_dir()
    end
  elseif vim.bo.buftype == '' then
    local path = vim.api.nvim_buf_get_name(0)
    if path ~= '' then
      dir = vim.fn.fnamemodify(path, ':p:h')
    end
  end

  if not dir or dir == '' or vim.fn.isdirectory(dir) == 0 then
    vim.notify(
      'OE: Cannot open file explorer - no current file or Oil directory.',
      vim.log.levels.WARN
    )
    return
  end

  vim.ui.open(dir)
end

local function open_html_from_oil()
  if vim.bo.filetype ~= 'oil' then
    vim.notify('OH: Must be used from an Oil buffer.', vim.log.levels.WARN)
    return
  end

  local ok, oil = pcall(require, 'oil')
  if not ok then
    vim.notify('OH: oil.nvim is unavailable.', vim.log.levels.ERROR)
    return
  end

  local dir = oil.get_current_dir()
  local entry = oil.get_cursor_entry()
  if not dir or not entry then
    vim.notify('OH: No Oil entry under cursor.', vim.log.levels.WARN)
    return
  end

  if entry.type ~= 'file' or not entry.name:lower():match('%.html$') then
    vim.notify('OH: Selected entry is not an .html file.', vim.log.levels.WARN)
    return
  end

  local path = dir .. entry.name
  local browser = vim.env.BROWSER
  local cmd = nil

  if browser and browser ~= '' then
    browser = vim.split(browser, ':')[1]
    cmd = vim.fn.split(browser)
    local path_inserted = false
    for i, arg in ipairs(cmd) do
      if arg:find('%%s') then
        cmd[i] = arg:gsub('%%s', path)
        path_inserted = true
      end
    end
    if not path_inserted then
      table.insert(cmd, path)
    end
  else
    for _, candidate in ipairs({
      'sensible-browser',
      'x-www-browser',
      'firefox',
      'chromium',
      'google-chrome',
      'brave-browser',
      'xdg-open',
    }) do
      if vim.fn.executable(candidate) == 1 then
        cmd = { candidate, path }
        break
      end
    end
  end

  if cmd then
    local jid = vim.fn.jobstart(cmd, { detach = true })
    if jid > 0 then
      return
    end
  end

  if vim.ui.open then
    vim.ui.open(path)
    return
  end

  vim.notify('OH: No browser command found.', vim.log.levels.ERROR)
end

-- stylua: ignore start
helpers.command_set_multi({
  { '', 'Help', custom_help.open, { desc = 'Open custom Neovim help' } },
  { '', 'HelpVue', custom_help.open_vue, { desc = 'Open Vue snippets help' } },
  { '', 'Bclean', Lpke_clean_buffers, { desc = 'Removes buffers that arent actively shown' } },

  -- terminal
  { '', 'TrashRestore', Lpke_trash_restore },
  { '*', 'T', Lpke_term }, -- arg: full
  { '*', 'Term', Lpke_term }, -- arg: full
  { '*', 'Terminal', Lpke_term }, -- arg: full
  { '*', 'R', Lpke_ranger }, -- arg: full
  { '*', 'Ranger', Lpke_ranger }, -- arg: full
  { '', 'OE', open_explorer_here, { desc = 'Open current file or Oil directory in OS file explorer' } },
  { '', 'OH', open_html_from_oil, { desc = 'Open selected Oil .html file in a browser' } },

  -- git
  { '*', 'Gpp', Lpke_gpp, { desc = 'Run zsh gpp helper without a terminal', bar = false } },

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
  { '', 'CU', codex_usage, { desc = 'Print Codex usage' } },
  { '', 'CodexUsage', codex_usage, { desc = 'Print Codex usage' } },

  -- yanking
  { '', 'Y', function() print('YP/p: buf name | YF: oil entry path | YD/d: cwd | YG/g: git root | YL/l: location | YT/t: tab ID | YB/b: buf ID | YW/w: win ID') end,
    { desc = 'Print help for `Y` commands' } },
  { '*', 'YP', function(cmd) Lpke_yank_buf_name(cmd, true) end }, -- arg: <register>
  { '*', 'Yp', function(cmd) Lpke_yank_buf_name(cmd, false) end }, -- arg: <register>
  { '*', 'YF', function(cmd) Lpke_yank_oil_entry_path(cmd, true) end }, -- arg: <register>
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
  { '', 'Cdc', function() Lpke_cd('', 'global') end, { desc = ':cd <nvim_global_cwd>' } },
  { '', 'Cdr', function() Lpke_cd('git', 'global') end, { desc = ':cd <git_root_or_cwd>' } },
  { '', 'Tcd', function() Lpke_cd_here('tab') end, { desc = ':tcd <current_dir>' } },
  { '', 'Tcdc', function() Lpke_cd('', 'tab') end, { desc = ':tcd <nvim_global_cwd>' } },
  { '', 'Tcdr', function() Lpke_cd('git', 'tab') end, { desc = ':tcd <git_root_or_cwd>' } },
  { '', 'Lcd', function() Lpke_cd_here('window') end, { desc = ':lcd <current_dir>' } },
  { '', 'Lcdc', function() Lpke_cd('', 'window') end, { desc = ':lcd <nvim_global_cwd>' } },
  { '', 'Lcdr', function() Lpke_cd('git', 'window') end, { desc = ':lcd <git_root_or_cwd>' } },
})
-- stylua: ignore end
