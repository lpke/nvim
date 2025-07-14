local M = {}

M.is_wsl = vim.fn.exists('$WSL_DISTRO_NAME') == 1

-- calls a function safely (non-breaking if error)
function M.safe_call(func, silent, fallback)
  local ok, result = pcall(func)
  if ok then
    return result
  else
    if not silent then
      vim.notify('safe_call error: ' .. result, vim.log.levels.ERROR)
    end
    return fallback
  end
end

-- merges all tables provided as args (later tables take priority)
function M.merge_tables(...)
  local combined_table = {}
  -- iterate over all provided tables
  for _, tbl in ipairs({ ... }) do
    for key, value in pairs(tbl) do
      combined_table[key] = value
    end
  end
  return combined_table
end

-- concatenates all arrays (itables) provided as args (in order)
function M.concat_arrs(...)
  local result_table = {}
  -- iterate over all provided tables
  for _, tbl in ipairs({ ... }) do
    for _, item in ipairs(tbl) do
      table.insert(result_table, item)
    end
  end
  return result_table
end

-- filter array (ipairs table) non-destructively
function M.arr_filter(arr, func)
  local filtered_arr = {}
  for index, item in ipairs(arr) do
    if func(item, index) then
      table.insert(filtered_arr, item)
    end
  end
  return filtered_arr
end

-- filter array in place (https://stackoverflow.com/questions/49709998/how-to-filter-a-lua-array-inplace)
function M.arr_filter_inplace(arr, func)
  local new_index = 1
  local size_orig = #arr
  for old_index, v in ipairs(arr) do
    if func(v, old_index) then
      arr[new_index] = v
      new_index = new_index + 1
    end
  end
  for i = new_index, size_orig do
    arr[i] = nil
  end
end

-- convert my options table into vim.opt.<key> = <value>
function M.set_options(options)
  for k, v in pairs(options) do
    vim.opt[k] = v
  end
end

-- parses a table containing custom keymap args and sets or deletes the keymap
function M.keymap_set(keymap)
  local mode, lhs, rhs, opts = table.unpack(keymap)
  opts = M.merge_tables({ noremap = true }, opts or {})
  local modes = {}
  local delete_only = false
  local mac_lhs = ''

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
    elseif char == 'M' then
      if lhs:find('<C%-') then
        mac_lhs = lhs:gsub('<C%-', '<D-')
      end
    else
      table.insert(modes, char)
    end
  end

  if delete_only then
    vim.keymap.del(modes, lhs, opts)
    if mac_lhs ~= '' then
      vim.keymap.del(modes, mac_lhs, opts)
    end
  else
    vim.keymap.set(modes, lhs, rhs, opts)
    if mac_lhs ~= '' then
      vim.keymap.set(modes, mac_lhs, rhs, opts)
    end
  end
end

-- same as above but accepts multiple keymap tables in a table
function M.keymap_set_multi(keymaps)
  for _i, keymap in ipairs(keymaps) do
    M.keymap_set(keymap)
  end
end

-- same as above but requires a filetype, and optionally accepts a condition function
function M.ft_keymap_set_multi(filetype_pattern, keymaps, cond_func)
  vim.api.nvim_create_autocmd({ 'FileType', 'BufEnter' }, {
    pattern = filetype_pattern,
    callback = function(event)
      local bufnr = event.buf
      -- run `cond_func` if provided
      if type(cond_func) == 'function' and (not cond_func(bufnr)) then
        return
      end
      -- add `buffer` option to every keymap
      for i, keymap in ipairs(keymaps) do
        local mode, lhs, rhs, opts = table.unpack(keymap)
        opts = opts or {}
        opts.buffer = bufnr
        keymaps[i] = { mode, lhs, rhs, opts }
      end
      M.keymap_set_multi(keymaps)
    end,
  })
end

function M.telescope_keymap_set_multi(target_title, keymaps, cond_func)
  M.ft_keymap_set_multi('TelescopePrompt', keymaps, function(bufnr)
    local ok, actions_state = pcall(require, 'telescope.actions.state')
    if not ok then
      return false
    end
    local prompt_title = actions_state.get_current_picker(bufnr).prompt_title
    if
      type(cond_func) == 'function' and (not cond_func(bufnr, prompt_title))
    then
      return false
    end
    return string.match(prompt_title, target_title) ~= nil
  end)
end

-- parses a table containing custom command args and creates or deletes the command
function M.command_set(command)
  local flags, name, cmd, opts = table.unpack(command)
  opts = M.merge_tables({}, opts or {})
  local delete_only = false

  for char in flags:gmatch('.') do
    if char == 'B' then
      opts.bang = true
    elseif char == 'R' then
      opts.range = true
    elseif char == 'D' then
      delete_only = true
    elseif char == '0' then -- no args allowed
      opts.nargs = 0
    elseif char == '1' then -- 1 arg required, unescaped spaces allowed
      opts.nargs = 1
    elseif char == '?' then -- 1 arg optional, unescaped spaces allowed
      opts.nargs = '?'
    elseif char == '+' then -- required many args
      opts.nargs = '+'
    elseif char == '*' then -- optional many args
      opts.nargs = '*'
    end
  end

  if delete_only then
    vim.api.nvim_del_user_command(name)
  else
    vim.api.nvim_create_user_command(name, cmd, opts)
  end
end

-- same as above but accepts multiple command tables in a table
function M.command_set_multi(commands)
  for _i, command in ipairs(commands) do
    M.command_set(command)
  end
end

-- pastes from register with unix line endings
function M.paste_unix(register, above)
  local content = vim.fn.getreg(register)
  local fixed_content = vim.fn.substitute(content, '\r\n', '\n', 'g')
  fixed_content = fixed_content:gsub('\n$', '')
  vim.fn.setreg(register, fixed_content)
  vim.cmd('normal! "' .. register .. (above and 'P' or 'p'))
end

-- getter and setters for highlight colors
function M.get_hl(name)
  return vim.api.nvim_get_hl(0, { name = name })
end
function M.set_hl(name, hl)
  vim.api.nvim_set_hl(0, name, hl)
end
function M.set_hl_multi(highlights)
  for name, hl in pairs(highlights) do
    M.set_hl(name, hl)
  end
end

-- toggle 'list' option (show whitespace chars)
function M.toggle_show_whitespace()
  local is_list = vim.wo.list
  vim.wo.list = not is_list
end

-- toggle global status line ('laststatus' option 2/3)
function M.toggle_global_status()
  if vim.o.laststatus == 3 then
    vim.o.laststatus = 2
  else
    vim.o.laststatus = 3
  end
end

-- prints a message 'over' the previous message
function M.print_over(msg, history, height)
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
function M.clear_last_message(target)
  local messages = vim.fn.execute('messages')
  local lines = vim.split(messages, '\n')
  local last_line = lines[#lines]

  if string.find(last_line, target, 1, true) then
    M.print_over(' ')
  end
end

-- yank still: upwards (up to `max`)
function M.keymap_set_yank_still_upwards(max)
  for i = 1, max do
    M.keymap_set({ 'nC', ('y' .. i .. 'k'), ('-' .. i .. ',.y') })
  end
end

-- yank still: marks (a-z)
function M.keymap_set_yank_still_marks()
  for i = string.byte('a'), string.byte('z') do
    local letter = string.char(i)
    M.keymap_set({ 'nC!', ("y'" .. letter), ("'" .. letter .. ',.y') })
  end
end

-- if `str` matches an item in `mappings`, return second value for it
-- eg: 'hello', {{'hello', 'hi'}, ...} -> 'hi'
function M.map_string(str, mappings, fallback)
  for _, map in ipairs(mappings) do
    if str == map[1] then
      return map[2]
    end
  end
  return fallback or str
end

-- get last segment of a path
function M.get_path_tail(str)
  return str:match('([^/]+/?/?)$')
end

-- get cwd folder name
function M.get_cwd_folder()
  local cwd = vim.fn.getcwd()
  return M.get_path_tail(cwd)
end

-- get current session name
function M.get_session_name(fallback)
  return M.safe_call(
    require('auto-session.lib').current_session_name,
    true,
    fallback
  )
end

-- check if session exists and matches cwd
function M.session_in_cwd()
  local cwd = M.get_cwd_folder()
  local session = M.get_session_name()
  return session and not (cwd == session)
end

-- call a function `count` times - for multiple args, use a table
function M.repeat_function(func, args, count)
  if type(args) == 'table' then
    args = function()
      return table.unpack(args)
    end
  end

  for _i = 1, count do
    func(args)
  end
end

-- check if cwd has .git folder
function M.cwd_has_git()
  return vim.fn.glob('.git/') ~= ''
end

-- stop currently focused terminal
function M.stop_term()
  vim.fn.jobstop(vim.b.terminal_job_id)
  vim.cmd('sleep 100m')
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<Esc>', true, true, true),
    'n',
    false
  )
end

-- refresh a telescope picker and optionally remember selection location
function M.refresh_picker(bufnr, remember, selection_defer_time)
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
    vim.notify('Error refreshing picker: ' .. result, vim.log.levels.ERROR)
  end
end

-- iterate over selection/s in a telescope picker
function M.telescope_sel_foreach(bufnr, func)
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
function M.remove_protocol(str)
  return str:gsub('^.*://', '')
end

-- get buf name (current if omitted), which is usually the path
function M.get_buf_name(bufnr, remove_protocol)
  bufnr = bufnr or 0
  local raw_buf_name = vim.api.nvim_buf_get_name(bufnr)
  local buf_name = remove_protocol and M.remove_protocol(raw_buf_name)
    or raw_buf_name
  return buf_name
end

-- get buf file type (current if omitted)
function M.get_file_type(bufnr)
  bufnr = bufnr or 0
  return vim.api.nvim_get_option_value('filetype', { buf = bufnr })
end

-- shorten a path (eg `plugins/lsp/test.lua` to `p/l/test.lua`)
function M.shorten_path(path)
  return path:gsub('([^/%w]?[^/])[^/]*/', '%1/')
end

-- transform full path string to a configurable relative path
function M.transform_path(full_path, opts)
  full_path = M.remove_protocol(full_path)
  opts = opts or {}
  local default_opts = {
    include_filename = true,
    dir_tail_slash = true,
    cwd_name = true,
    shorten = false,
  }
  opts = M.merge_tables(default_opts, opts)

  local mods = ':p:~:.' .. (opts.include_filename and '' or ':h')
  local rel_path = vim.fn.fnamemodify(full_path, mods)

  if opts.cwd_name and rel_path == '.' then
    rel_path = M.get_cwd_folder()
  end

  if opts.shorten then
    rel_path = M.shorten_path(rel_path)
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

function M.find_upward_to_git_root_or_cwd(items)
  local cur_dir = vim.fn.fnamemodify(vim.fn.expand('%:p'), ':h')
  local root = Lpke_find_git_root() or vim.fn.getcwd()
  while cur_dir and cur_dir ~= '/' do
    for _, item in ipairs(items) do
      local path
      if item:sub(-1) == '/' then
        -- item is a directory
        path = cur_dir .. '/' .. item:sub(1, -2)
        if vim.fn.isdirectory(path) == 1 then
          return path .. '/'
        end
      else
        -- item is a file
        path = cur_dir .. '/' .. item
        if vim.fn.filereadable(path) == 1 then
          return path
        end
      end
    end
    if cur_dir == root then
      break
    end
    local parent = vim.fn.fnamemodify(cur_dir, ':h')
    if parent == cur_dir then
      break
    end
    cur_dir = parent
  end
  return nil
end

-- execute a string as Lua code
function M.execute_as_lua(code_string)
  local func, err = load('return ' .. code_string)
  if func then
    return func()
  else
    vim.notify(err or 'unknown error', vim.log.levels.ERROR)
  end
end

-- quickfix navigation: direction = 1 (next), -1 (prev)
function M.qf_nav(direction)
  M.safe_call(function()
    local qf = vim.fn.getqflist({ idx = 0 })
    local qf_size = #vim.fn.getqflist()
    local qf_idx = qf.idx
    if qf_size == 1 then
      vim.cmd('cfirst')
      return
    end
    if direction == 1 then
      if qf_idx == qf_size then
        vim.cmd('clast')
        if vim.fn.getqflist({ idx = 0 }).idx == qf_size then
          vim.notify('Already at last quickfix item', vim.log.levels.INFO)
        end
      else
        vim.cmd('cnext')
      end
    else
      if qf_idx == 1 then
        vim.cmd('cfirst')
        if vim.fn.getqflist({ idx = 0 }).idx == 1 then
          vim.notify('Already at first quickfix item', vim.log.levels.INFO)
        end
      else
        vim.cmd('cprev')
      end
    end
  end, true)
end

return M
