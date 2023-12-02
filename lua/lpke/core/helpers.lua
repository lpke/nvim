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

-- combines two tables (newTable takes priority) without mutating defaultTable
function E.combine_tables(defaultTable, newTable)
  local combinedTable = {}
  -- copy defaultTable into combinedTable
  for k, v in pairs(defaultTable) do
    combinedTable[k] = v
  end
  -- merge newTable into combinedTable
  for k, v in pairs(newTable) do
    combinedTable[k] = v
  end
  return combinedTable
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
function E.paste_unix(register, above)
  local content = vim.fn.getreg(register)
  local fixed_content = vim.fn.substitute(content, '\r\n', '\n', 'g')
  fixed_content = fixed_content:gsub('\n$', '')
  vim.fn.setreg(register, fixed_content)
  vim.cmd('normal! "' .. register .. (above and 'P' or 'p'))
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
  return str:match('([^/]+/?/?)$')
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

-- stop currently focused terminal
function E.stop_term()
  vim.fn.jobstop(vim.b.terminal_job_id)
  vim.cmd('sleep 100m')
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<Esc>', true, true, true),
    'n',
    false
  )
end

-- refresh a telescope picker and optionally remember selection location
function E.refresh_picker(bufnr, remember, selection_defer_time)
  selection_defer_time = selection_defer_time or 5
  if remember == nil then
    remember = true
  end
  local ok, result = pcall(function()
    local actions_state = require('telescope.actions.state')
    local picker = actions_state.get_current_picker(bufnr)
    local index = picker._selection_row
    picker:refresh()
    if remember then
      vim.defer_fn(function()
        picker:set_selection(index)
      end, selection_defer_time)
    end
  end)

  if not ok then
    print('Error refreshing picker: ' .. result)
  end
end

-- iterate over selection/s in a telescope picker
function E.telescope_sel_foreach(bufnr, func)
  local actions_state = require('telescope.actions.state')
  local actions_utils = require('telescope.actions.utils')

  local selections = {}
  actions_utils.map_selections(bufnr, function(entry)
    table.insert(selections, entry)
  end)

  if #selections == 0 then
    local selection = actions_state.get_selected_entry(bufnr)
    func(selection)
  else
    for _, v in ipairs(selections) do
      func(v)
    end
  end
end

-- remove the protocol (eg `oil://` or `oil-trash://`) from a string
function E.remove_protocol(str)
  return str:gsub('^.*://', '')
end

-- get buf name (current if omitted), which is usually the path
function E.get_buf_name(bufnr, remove_protocol)
  bufnr = bufnr or 0
  local raw_buf_name = vim.api.nvim_buf_get_name(bufnr)
  local buf_name = remove_protocol and E.remove_protocol(raw_buf_name)
    or raw_buf_name
  return buf_name
end

-- shorten a path (eg `plugins/lsp/test.lua` to `p/l/test.lua`)
function E.shorten_path(path)
  return path:gsub('([^/%w]?[^/])[^/]*/', '%1/')
end

-- transform full path string to a configurable relative path
function E.transform_path(full_path, opts)
  full_path = E.remove_protocol(full_path)
  opts = opts or {}
  local default_opts = {
    include_filename = true,
    dir_tail_slash = true,
    cwd_name = true,
    shorten = false,
  }
  opts = E.combine_tables(default_opts, opts)

  local mods = ':p:~:.' .. (opts.include_filename and '' or ':h')
  local rel_path = vim.fn.fnamemodify(full_path, mods)

  if opts.cwd_name and rel_path == '.' then
    rel_path = E.get_cwd_folder()
  end

  if opts.shorten then
    rel_path = E.shorten_path(rel_path)
  end

  if
    opts.dir_tail_slash
    and not opts.include_filename
    and (string.sub(rel_path, -1) ~= '/')
  then
    rel_path = rel_path .. '/'
  end

  return rel_path
end

return E
