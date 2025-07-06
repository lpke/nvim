local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local builtin = require('telescope.builtin')
local helpers = require('lpke.core.helpers')
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local previewers = require('telescope.previewers')

local tc = Lpke_theme_colors

local keymaps = {
  file_dir_switch = { '<F2>s', '<A-s>' },
  cwd_change = { '<BS><BS>' },
  cwd_change_grep = { '<BS>/' },
}

local E = {}

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

local function switch_to_picker(cur_prompt_buf, picker_func, keep_query)
  local current_picker = action_state.get_current_picker(cur_prompt_buf)
  local current_query = current_picker:_get_prompt()
  local current_cwd = current_picker.cwd
  actions.close(cur_prompt_buf)

  local opts = {}
  if current_cwd then
    opts.cwd = current_cwd
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

  local path = selection.value or selection.path or selection[1]
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

-- Helper function to setup common keymaps for both pickers
local function setup_common_keymaps(prompt_bufnr, map, is_directory_picker)
  -- Switch picker keymaps
  for _, keymap in ipairs(keymaps.file_dir_switch) do
    local target_func = is_directory_picker and E.find_files
      or E.find_directories
    map('i', keymap, function()
      switch_to_picker(prompt_bufnr, target_func, true)
    end)
    map('n', keymap, function()
      switch_to_picker(prompt_bufnr, target_func, true)
    end)
  end

  -- Parent directory navigation keymaps
  for _, keymap in ipairs(keymaps.cwd_change) do
    map('n', keymap, function()
      local parent_dir =
        get_selection_parent_dir(prompt_bufnr, is_directory_picker)

      actions.close(prompt_bufnr)

      local target_func = is_directory_picker and E.find_directories
        or E.find_files
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

    local target_func = is_directory_picker and E.find_directories
      or E.find_files
    target_func({
      cwd = parent_dir,
      initial_mode = 'normal',
    })
  end)
end

function E.find_git_files()
  if helpers.cwd_has_git() then
    builtin.git_files()
  else
    builtin.find_files()
  end
end
function E.grep_yanked()
  builtin.grep_string({ search = vim.fn.getreg('"') })
end
function E.grep_custom()
  builtin.grep_string({ search = vim.fn.input('Grep: ') })
end

function E.find_directories(opts)
  opts = opts or {}
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

  pickers
    .new({}, {
      prompt_title = 'Find Directories',
      cwd = opts.cwd,
      initial_mode = opts.initial_mode or 'insert',
      default_text = initial_query,
      finder = finders.new_oneshot_job({
        'find',
        opts.cwd or '.',
        '-type',
        'd',
        '-not',
        '-path',
        '*/.*',
        '-not',
        '-path',
        '*/node_modules',
        '-not',
        '-path',
        '*/node_modules/*',
      }, {
        entry_maker = function(entry)
          if should_ignore_dir(entry) then
            return nil
          end
          -- Remove './' prefix and append '/' suffix
          local clean_entry = entry:gsub('^%./', '') .. '/'
          return {
            value = entry,
            display = clean_entry,
            ordinal = clean_entry,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
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

          local entries = scan_directory(entry.value)
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
      attach_mappings = function(prompt_bufnr, map)
        -- Setup common keymaps
        setup_common_keymaps(prompt_bufnr, map, true)

        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd('Oil ' .. selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

-- extends default find files picker
function E.find_files(opts)
  opts = opts or {}
  local initial_query = opts.default_text or ''

  -- Update gap path when cwd is specified
  if opts.cwd then
    update_gap_path(opts.cwd)
  else
    gap_path = ''
  end

  -- Set default_text for the builtin picker
  opts.default_text = initial_query

  -- Add custom attach_mappings to extend the builtin picker
  local original_attach_mappings = opts.attach_mappings
  opts.attach_mappings = function(prompt_bufnr, map)
    -- Call original attach_mappings if it exists
    if original_attach_mappings then
      original_attach_mappings(prompt_bufnr, map)
    end

    -- Setup common keymaps
    setup_common_keymaps(prompt_bufnr, map, false)

    return true
  end

  -- Use the builtin find_files with our enhanced options
  builtin.find_files(opts)
end

-- use find_files or find_directories depending on if editing a file or in oil buffer
function E.smart_find()
  if vim.bo.filetype == 'oil' then
    E.find_directories()
  else
    E.find_files()
  end
end

return E
