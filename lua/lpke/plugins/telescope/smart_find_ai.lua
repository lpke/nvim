-- TODO: refactor then deprecate this file

local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local builtin = require('telescope.builtin')
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local make_entry = require('telescope.make_entry')
local config_values = require('telescope.config').values
local previewers = require('telescope.previewers')
local ts_helpers = require('lpke.plugins.telescope.helpers')

local tc = Lpke_theme_colors

local keymaps = {
  file_dir_switch = { '<F2>s', '<A-s>' },
  cwd_change = { '<BS><BS>' },
  cwd_change_grep = { '<BS>/' },
}

local M = {}

-- Store the gap path between nvim's cwd and telescope's cwd
local gap_path = ''

-- Helper function to calculate and store the gap path
local function update_gap_path(telescope_cwd)
  local nvim_cwd = vim.fn.getcwd()
  if telescope_cwd == nvim_cwd then
    gap_path = ''
  else
    -- Calculate relative path from nvim_cwd to telescope_cwd
    gap_path = vim.fn.fnamemodify(telescope_cwd, ':.')
    if gap_path == telescope_cwd then
      -- telescope_cwd is absolute and not under nvim_cwd
      gap_path = telescope_cwd
    end
  end
end

-- Helper function to resolve path relative to nvim's cwd
local function resolve_path_from_nvim_cwd(relative_path)
  if gap_path == '' then
    return relative_path
  end

  -- If gap_path is absolute, join directly
  if vim.fn.fnamemodify(gap_path, ':p') == gap_path then
    return gap_path .. '/' .. relative_path
  end

  -- Otherwise, gap_path is relative to nvim_cwd
  return gap_path .. '/' .. relative_path
end

local function switch_to_picker(
  cur_prompt_buf,
  picker_func,
  keep_query,
  initial_mode
)
  local current_picker = action_state.get_current_picker(cur_prompt_buf)
  local current_query = current_picker:_get_prompt()
  local current_cwd = current_picker.cwd
  actions.close(cur_prompt_buf)

  local opts = {}
  if current_cwd then
    opts.cwd = current_cwd
  end
  if initial_mode then
    opts.initial_mode = initial_mode
  end

  if keep_query then
    opts.default_text = current_query
    picker_func(opts)
  else
    picker_func(opts)
  end
end

local function get_selection_parent_dir(_prompt_bufnr, is_directory_picker)
  local selection = action_state.get_selected_entry()
  if not selection then
    return vim.fn.getcwd()
  end

  local path = selection.path or selection.value or selection[1]
  if not path then
    return vim.fn.getcwd()
  end

  -- For directory pickers, use the selected directory directly
  -- For file pickers, get the parent directory
  if is_directory_picker then
    return path
  end

  -- If it's a directory, use it directly; if it's a file, get its parent
  if vim.fn.isdirectory(path) == 1 then
    return path
  else
    return vim.fn.fnamemodify(path, ':h')
  end
end

local function find_files_picker_config(opts)
  local pconf = require('telescope.config').pickers.find_files or {}
  local defaults = pconf.theme
      and require('telescope.themes')['get_' .. pconf.theme](pconf)
    or vim.deepcopy(pconf)

  return vim.tbl_extend('force', defaults, opts or {})
end

local function find_files_command(opts, path_arg)
  local find_command = opts.find_command

  if type(find_command) == 'function' then
    find_command = find_command(opts)
  end

  if find_command then
    find_command = vim.deepcopy(find_command)
  elseif vim.fn.executable('rg') == 1 then
    find_command = { 'rg', '--files', '--color', 'never' }
  elseif vim.fn.executable('fd') == 1 then
    find_command = { 'fd', '--type', 'f', '--color', 'never' }
  elseif vim.fn.executable('fdfind') == 1 then
    find_command = { 'fdfind', '--type', 'f', '--color', 'never' }
  elseif vim.fn.executable('find') == 1 and vim.fn.has('win32') == 0 then
    find_command = { 'find', '.', '-type', 'f' }
  end

  if not find_command then
    return nil
  end

  local command = find_command[1]
  if command == 'fd' or command == 'fdfind' or command == 'rg' then
    if opts.hidden then
      table.insert(find_command, '--hidden')
    end
    if opts.no_ignore then
      table.insert(find_command, '--no-ignore')
    end
    if opts.no_ignore_parent then
      table.insert(find_command, '--no-ignore-parent')
    end
    if opts.follow then
      table.insert(find_command, '-L')
    end
  end

  if path_arg then
    if command == 'rg' then
      vim.list_extend(find_command, { '--', path_arg })
    elseif command == 'fd' or command == 'fdfind' then
      vim.list_extend(find_command, { '.', path_arg })
    elseif command == 'find' then
      if find_command[2] == '.' then
        find_command[2] = path_arg
      else
        table.insert(find_command, 2, path_arg)
      end
    else
      table.insert(find_command, path_arg)
    end
  end

  return find_command
end

local function prompt_root_key(parsed)
  if not parsed.has_cwd_arg then
    return ''
  end
  return parsed.cwd .. '\n' .. parsed.path_arg
end

local function find_files_finder(opts, parsed)
  local entry_maker = opts.entry_maker or make_entry.gen_from_file(opts)

  if parsed.has_cwd_arg and not parsed.valid_cwd then
    return finders.new_table({
      results = {},
      entry_maker = entry_maker,
    })
  end

  local command =
    find_files_command(opts, parsed.has_cwd_arg and parsed.path_arg or nil)

  if not command then
    vim.notify(
      'smart_find_ai.find_files: install rg, fd, fdfind, or find',
      vim.log.levels.ERROR
    )
    return finders.new_table({
      results = {},
      entry_maker = entry_maker,
    })
  end

  return finders.new_oneshot_job(
    command,
    vim.tbl_extend('force', opts, { entry_maker = entry_maker })
  )
end

local function is_absolute_path(path)
  return path:sub(1, 1) == '/'
    or path:match('^%a:[/\\]') ~= nil
    or path:sub(1, 2) == '\\\\'
end

local function absolute_path(cwd, path)
  if is_absolute_path(path) then
    return path
  end
  return vim.fs.joinpath(cwd, path)
end

local function find_directories_command(path_arg)
  local command = {
    'fd',
    '--hidden', -- do not ignore `.` dirs
    '--type',
    'd',
    '--exclude',
    '.git',
    '--exclude',
    'node_modules',
  }

  if path_arg then
    vim.list_extend(command, {
      '.',
      path_arg,
    })
  end

  return command
end

local function find_directories_entry_maker(opts, should_ignore_dir)
  local cwd = opts.cwd
  return function(entry)
    if should_ignore_dir(entry) then
      return nil
    end
    return {
      value = entry,
      path = absolute_path(cwd, entry),
      display = entry,
      ordinal = entry,
    }
  end
end

local function find_directories_finder(opts, parsed, should_ignore_dir)
  local entry_maker = find_directories_entry_maker(opts, should_ignore_dir)

  if parsed.has_cwd_arg and not parsed.valid_cwd then
    return finders.new_table({
      results = {},
      entry_maker = entry_maker,
    })
  end

  return finders.new_oneshot_job(
    find_directories_command(parsed.has_cwd_arg and parsed.path_arg or nil),
    vim.tbl_deep_extend('force', {
      entry_maker = entry_maker,
    }, opts)
  )
end

-- Helper function to setup common keymaps for both pickers
local function setup_common_keymaps(prompt_bufnr, map, is_directory_picker)
  -- Switch picker keymaps
  for _, keymap in ipairs(keymaps.file_dir_switch) do
    local target_func = is_directory_picker and M.find_files
      or M.find_directories
    map('i', keymap, function()
      switch_to_picker(prompt_bufnr, target_func, true, 'insert')
    end)
    map('n', keymap, function()
      switch_to_picker(prompt_bufnr, target_func, true, 'normal')
    end)
  end

  -- Parent directory navigation keymaps
  for _, keymap in ipairs(keymaps.cwd_change) do
    map('n', keymap, function()
      local parent_dir =
        get_selection_parent_dir(prompt_bufnr, is_directory_picker)

      actions.close(prompt_bufnr)

      local target_func = is_directory_picker and M.find_directories
        or M.find_files
      target_func({
        cwd = parent_dir,
      })
    end)
  end

  -- Parent directory live grep keymaps
  for _, keymap in ipairs(keymaps.cwd_change_grep) do
    map('n', keymap, function()
      local parent_dir =
        get_selection_parent_dir(prompt_bufnr, is_directory_picker)

      -- Resolve the path relative to nvim's cwd
      local resolved_parent_dir = resolve_path_from_nvim_cwd(parent_dir)

      actions.close(prompt_bufnr)

      builtin.live_grep({
        cwd = resolved_parent_dir,
      })
    end)
  end

  -- Navigate up one directory level with `-` in normal mode
  map('n', '-', function()
    local current_picker = action_state.get_current_picker(prompt_bufnr)
    local current_cwd = current_picker.cwd or vim.fn.getcwd()
    local parent_dir = vim.fn.fnamemodify(current_cwd, ':h')

    actions.close(prompt_bufnr)

    local target_func = is_directory_picker and M.find_directories
      or M.find_files
    target_func({
      cwd = parent_dir,
      initial_mode = 'normal',
    })
  end)
end

function M.find_directories(opts)
  opts = opts or {}
  opts.cwd = ts_helpers.normalize_cwd(opts.cwd or vim.fn.getcwd())
  if vim.fn.isdirectory(opts.cwd) ~= 1 then
    opts.cwd = ts_helpers.normalize_cwd(vim.fn.getcwd())
  end

  local initial_query = opts.default_text or ''

  -- Update gap path when cwd is specified
  if opts.cwd then
    update_gap_path(opts.cwd)
  else
    gap_path = ''
  end

  -- Read and prepare .gitignore patterns
  local gitignore_patterns = {}
  local gitignore_file = vim.fn.findfile('.gitignore', '.;')
  if gitignore_file ~= '' then
    local gitignore_content = vim.fn.readfile(gitignore_file)
    for _, pattern in ipairs(gitignore_content) do
      -- Skip empty lines and comments
      if pattern ~= '' and not pattern:match('^#') then
        -- Remove trailing slash for directory patterns
        local clean_pattern = pattern:gsub('/$', '')
        table.insert(gitignore_patterns, clean_pattern)
      end
    end
  end

  local function should_ignore_dir(dir_path)
    for _, pattern in ipairs(gitignore_patterns) do
      if dir_path:match(pattern) or dir_path:match(pattern .. '$') then
        return true
      end
    end
    return false
  end

  opts.default_text = initial_query
  local parsed_prompt = ts_helpers.parse_prompt_cwd(initial_query, opts.cwd)
  local current_root_key = prompt_root_key(parsed_prompt)
  local original_on_input_filter_cb = opts.on_input_filter_cb

  opts.on_input_filter_cb = function(prompt)
    parsed_prompt = ts_helpers.parse_prompt_cwd(prompt, opts.cwd)
    local result = original_on_input_filter_cb
        and original_on_input_filter_cb(parsed_prompt.prompt)
      or {}

    result.prompt = result.prompt or parsed_prompt.prompt

    local next_root_key = prompt_root_key(parsed_prompt)
    if next_root_key ~= current_root_key then
      current_root_key = next_root_key
      result.updated_finder =
        find_directories_finder(opts, parsed_prompt, should_ignore_dir)
    end

    return result
  end

  local original_attach_mappings = opts.attach_mappings
  opts.attach_mappings = function(prompt_bufnr, map)
    if original_attach_mappings then
      original_attach_mappings(prompt_bufnr, map)
    end

    setup_common_keymaps(prompt_bufnr, map, true)

    actions.select_default:replace(function()
      actions.close(prompt_bufnr)
      local selection = action_state.get_selected_entry()
      if selection then
        vim.cmd('Oil ' .. vim.fn.fnameescape(selection.path or selection.value))
      end
    end)
    return true
  end

  pickers
    .new(opts, {
      prompt_title = 'Find Directories',
      cwd = opts.cwd,
      initial_mode = opts.initial_mode or 'insert',
      default_text = initial_query,
      finder = find_directories_finder(opts, parsed_prompt, should_ignore_dir),
      sorter = config_values.generic_sorter({}),
      previewer = previewers.new_buffer_previewer({
        title = 'Directory Contents',
        define_preview = function(self, entry)
          local function scan_directory(path)
            local ok, entries = pcall(vim.fn.readdir, path, function(name)
              return name ~= '.' and name ~= '..'
            end)
            if not ok then
              return {}
            end

            local dirs, files = {}, {}
            for _, name in ipairs(entries) do
              local full_path = path .. '/' .. name
              if vim.fn.isdirectory(full_path) == 1 then
                table.insert(dirs, name .. '/')
              else
                table.insert(files, name)
              end
            end

            table.sort(dirs)
            table.sort(files)

            local result = {}
            vim.list_extend(result, dirs)
            vim.list_extend(result, files)
            return result
          end

          local entries = scan_directory(entry.path or entry.value)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, entries)
          vim.bo[self.state.bufnr].filetype = 'oil'

          vim.api.nvim_buf_call(self.state.bufnr, function()
            vim.cmd('syntax clear')
            vim.cmd('syntax match TelescopePreviewDirectory ".*/$"')
            vim.api.nvim_set_hl(
              0,
              'TelescopePreviewDirectory',
              { fg = tc.foam }
            )
          end)
        end,
      }),
    })
    :find()
end

-- extends default find files picker
function M.find_files(opts)
  opts = find_files_picker_config(opts)
  opts.cwd = ts_helpers.normalize_cwd(opts.cwd or vim.fn.getcwd())
  if vim.fn.isdirectory(opts.cwd) ~= 1 then
    opts.cwd = ts_helpers.normalize_cwd(vim.fn.getcwd())
  end

  local initial_query = opts.default_text or ''

  -- Update gap path when cwd is specified
  if opts.cwd then
    update_gap_path(opts.cwd)
  else
    gap_path = ''
  end

  -- Set default_text for the builtin picker
  opts.default_text = initial_query

  local parsed_prompt = ts_helpers.parse_prompt_cwd(initial_query, opts.cwd)
  local current_root_key = prompt_root_key(parsed_prompt)
  local original_on_input_filter_cb = opts.on_input_filter_cb

  opts.on_input_filter_cb = function(prompt)
    parsed_prompt = ts_helpers.parse_prompt_cwd(prompt, opts.cwd)
    local result = original_on_input_filter_cb
        and original_on_input_filter_cb(parsed_prompt.prompt)
      or {}

    result.prompt = result.prompt or parsed_prompt.prompt

    local next_root_key = prompt_root_key(parsed_prompt)
    if next_root_key ~= current_root_key then
      current_root_key = next_root_key
      result.updated_finder = find_files_finder(opts, parsed_prompt)
    end

    return result
  end

  -- Add custom attach_mappings to extend the builtin picker
  local original_attach_mappings = opts.attach_mappings
  opts.attach_mappings = function(prompt_bufnr, map)
    -- Call original attach_mappings if it exists
    if original_attach_mappings then
      original_attach_mappings(prompt_bufnr, map)
    end

    -- Setup common keymaps
    setup_common_keymaps(prompt_bufnr, map, false)

    -- Open oil window at selected file's directory with <leader><CR>
    map('n', '<leader><CR>', function()
      local selection = action_state.get_selected_entry()
      if selection then
        local file_path = selection.value or selection.path or selection[1]
        if file_path then
          local dir_path = vim.fn.isdirectory(file_path) == 1 and file_path
            or vim.fn.fnamemodify(file_path, ':h')
          actions.close(prompt_bufnr)
          vim.cmd('Oil ' .. dir_path)
        end
      end
    end)

    return true
  end

  pickers
    .new(opts, {
      prompt_title = 'Find Files',
      __locations_input = true,
      finder = find_files_finder(opts, parsed_prompt),
      previewer = config_values.grep_previewer(opts),
      sorter = config_values.file_sorter(opts),
    })
    :find()
end

-- use find_files or find_directories depending on if editing a file or in oil buffer
function M.smart_find(opts)
  opts = opts or {}

  if vim.bo.filetype == 'oil' then
    -- M.find_directories()
    -- revert to 'find_files' default for now
    M.find_files(opts)
  else
    M.find_files(opts)
  end
end

return M
