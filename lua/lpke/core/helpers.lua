local E = {}

E.is_wsl = vim.fn.exists('$WSL_DISTRO_NAME')

-- calls a function safely (non-breaking if error)
function E.safe_call(func, silent, fallback)
  local ok, result = pcall(func)
  if ok then
    return result
  else
    if not silent then
      print('safe_call error: ' .. result)
    end
    return fallback
  end
end

function E.combine_tables(defaultTable, newTable)
  for k, v in pairs(newTable) do
    defaultTable[k] = v
  end
  return defaultTable
end

-- convert my options table into vim.opt.<key> = <value>
function E.set_options(options)
  for k, v in pairs(options) do
    vim.opt[k] = v
  end
end

-- parses a table containing custom keymap args and sets or deletes the keymap
function E.keymap_set(keymap)
  local mode, lhs, rhs, opts = table.unpack(keymap)
  opts = E.combine_tables({ noremap = true }, opts or {})
  local modes = {}
  local delete_only = false

  for char in mode:gmatch('.') do
    if char == 'R' then
      opts.noremap = false
    elseif char == 'E' then
      opts.expr = true
    elseif char == 'C' then
      rhs = '<cmd>' .. rhs .. '<cr>'
    elseif char == '!' then
      opts.silent = true
    elseif char == 'D' then
      delete_only = true
    else
      table.insert(modes, char)
    end
  end

  if delete_only then
    vim.keymap.del(modes, lhs, opts)
  else
    vim.keymap.set(modes, lhs, rhs, opts)
  end
end

-- same as above but accepts multiple keymap tables in a table
function E.keymap_set_multi(keymaps)
  for _i, keymap in ipairs(keymaps) do
    E.keymap_set(keymap)
  end
end

-- pastes from register with unix line endings
function E.paste_unix(register)
  local content = vim.fn.getreg(register)
  local fixed_content = vim.fn.substitute(content, '\r\n', '\n', 'g')
  vim.fn.setreg(register, fixed_content)
  vim.cmd('normal! "' .. register .. 'p')
end

-- getter and setters for highlight colors
function E.get_hl(name)
  return vim.api.nvim_get_hl(0, { name = name })
end
function E.set_hl(name, hl)
  vim.api.nvim_set_hl(0, name, hl)
end

-- toggle 'list' option (show whitespace chars) and highlight
local non_text_hl = {}
local has_toggled_whitespace = false
function E.toggle_whitespace_hl(hl_name)
  if not has_toggled_whitespace then
    non_text_hl = E.get_hl('NonText')
    has_toggled_whitespace = true
  end

  local is_list = vim.wo.list
  vim.wo.list = not is_list

  if not is_list then -- if not *previously*
    local target_hl = E.get_hl(hl_name)
    E.set_hl('NonText', { fg = target_hl.fg, bg = target_hl.bg })
  else
    E.set_hl('NonText', non_text_hl)
  end
end

-- toggle global status line ('laststatus' option 2/3)
function E.toggle_global_status()
  if vim.o.laststatus == 3 then
    vim.o.laststatus = 2
  else
    vim.o.laststatus = 3
  end
end

-- prints a message 'over' the previous message
function E.print_over(msg, history, height)
  history = history or false
  local orig_height = vim.o.cmdheight
  vim.o.cmdheight = height or 2
  if history then
    print(msg)
  else
    vim.cmd('echo "' .. msg .. '"')
  end
  vim.o.cmdheight = orig_height
end

-- clear the latest message if it contains `target`
function E.clear_last_message(target)
  local messages = vim.fn.execute('messages')
  local lines = vim.split(messages, '\n')
  local last_line = lines[#lines]

  if string.find(last_line, target, 1, true) then
    E.print_over(' ')
  end
end

-- yank still: upwards (up to `max`)
function E.keymap_set_yank_still_upwards(max)
  for i = 1, max do
    E.keymap_set({ 'nC', ('y' .. i .. 'k'), ('-' .. i .. ',.y') })
  end
end

-- yank still: marks (a-z)
function E.keymap_set_yank_still_marks()
  for i = string.byte('a'), string.byte('z') do
    local letter = string.char(i)
    E.keymap_set({ 'nC!', ("y'" .. letter), ("'" .. letter .. ',.y') })
  end
end

-- if `str` matches an item in `mappings`, return second value for it
-- eg: 'hello', {{'hello', 'hi'}, ...} -> 'hi'
function E.map_string(str, mappings, fallback)
  for _, map in ipairs(mappings) do
    if str == map[1] then
      return map[2]
    end
  end
  return fallback or str
end

-- get last segment of a path
function E.get_path_tail(str)
  return str:match('([^/]+)$')
end

-- get cwd folder name
function E.get_cwd_folder()
  local cwd = vim.fn.getcwd()
  return E.get_path_tail(cwd)
end

-- get current session name
function E.get_session_name(fallback)
  return E.safe_call(
    require('auto-session.lib').current_session_name,
    true,
    fallback
  )
end

-- check if session exists and matches cwd
function E.session_in_cwd()
  local cwd = E.get_cwd_folder()
  local session = E.get_session_name()
  return session and not (cwd == session)
end

-- format current session name for status line
function E.formatted_session_name(symbol)
  local session = E.get_session_name()
  if session and symbol then
    return symbol .. session
  else
    return session
  end
end

-- call a function `count` times - for multiple args, use a table
function E.repeat_function(func, args, count)
  if type(args) == 'table' then
    args = function()
      return table.unpack(args)
    end
  end

  for i = 1, count do
    func(args)
  end
end

-- check if cwd has .git folder
function E.cwd_has_git()
  return vim.fn.glob('.git/') ~= ''
end

-- window 'zoom' toggling (with per tab support)
Lpke_zoomed = {} -- stores whether tab group/s are in a 'zoomed' state or not
Lpke_zoom_previous = {} -- stores state of previous window layouts
Lpke_zoom_count = {} -- stores number of number of windows at time of last zoom
function Lpke_zoomed_reset_state(equalise)
  Lpke_zoomed = {}
  Lpke_zoom_previous = {}
  Lpke_zoom_count = {}
  if equalise then
    vim.cmd('wincmd =')
  end
end
function E.win_zoom_toggle()
  local ok, err = pcall(function()
    local cur_tab = vim.api.nvim_get_current_tabpage()
    local cur_win = vim.api.nvim_get_current_win()

    if Lpke_zoomed[cur_tab] then
      local wins = vim.api.nvim_tabpage_list_wins(cur_tab)
      if #wins >= Lpke_zoom_count[cur_tab] then
        -- restore the previous layout
        for _, win_info in ipairs(Lpke_zoom_previous[cur_tab]) do
          local win = win_info.win
          vim.api.nvim_set_current_win(win)
          vim.cmd(string.format('resize %d', win_info.height))
          vim.cmd(string.format('vertical resize %d', win_info.width))
        end
        Lpke_zoomed_reset_state()
      else
        print(
          'Un-Zoom: Could not restore previous sizing: Less windows than expected.'
        )
        Lpke_zoomed_reset_state(true)
      end
    else
      -- save layout and zoom current window
      local wins = vim.api.nvim_tabpage_list_wins(cur_tab)
      if #wins > 1 then
        Lpke_zoom_previous[cur_tab] = {}
        Lpke_zoom_count[cur_tab] = #wins
        for _, win in ipairs(wins) do
          local height = vim.api.nvim_win_get_height(win)
          local width = vim.api.nvim_win_get_width(win)
          table.insert(
            Lpke_zoom_previous[cur_tab],
            { win = win, height = height, width = width }
          )
        end
        vim.api.nvim_set_current_win(cur_win)
        vim.cmd('wincmd |')
        vim.cmd('wincmd _')
        Lpke_zoomed[cur_tab] = true
      end
    end

    -- restore focus to the original window
    vim.api.nvim_set_current_win(cur_win)
  end)

  -- error occured
  if not ok then
    Lpke_zoomed_reset_state()
    print('Zoom: Encountered an error: ' .. err)
  end

  -- update lualine
  pcall(function()
    require('lualine').refresh()
  end)
end

return E
