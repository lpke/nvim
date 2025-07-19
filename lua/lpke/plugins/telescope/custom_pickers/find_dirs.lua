-- TODO: write this custom picker

local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
-- local sorters = require('telescope.sorters')
local previewers = require('telescope.previewers')
local config_values = require('telescope.config').values
-- local make_entry = require('telescope.make_entry')

local tc = Lpke_theme_colors

local find_dirs = function(opts)
  opts = opts or {}

  -- cwd priority order:
  -- explicit cwd, git_root (if true), current nvim global cwd
  if not opts.cwd then
    if opts.git_cwd then
      opts.cwd = Lpke_find_git_root() or vim.fn.getcwd(-1, -1)
    else
      opts.cwd = vim.fn.getcwd(-1, -1)
    end
  end
  -- ensure cwd is valid
  if not vim.fn.isdirectory(opts.cwd) ~= 1 then
    opts.cwd = vim.fn.getcwd(-1, -1)
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

  local finder = finders.new_async_job({
    cwd = opts.cwd,
    command_generator = function(_prompt)
      return {
        'find',
        opts.cwd or '.',
        '-type',
        'd',
        '(',
        '-name',
        '.git',
        '-o',
        '-name',
        'node_modules',
        ')',
        '-prune',
        '-o',
        '-type',
        'd',
        '-print',
      }
    end,
    entry_maker = function(entry)
      if should_ignore_dir(entry) then
        return nil
      end
      -- Make path relative to git root
      local relative_path = entry
      if opts.cwd and entry:sub(1, #opts.cwd) == opts.cwd then
        relative_path = entry:sub(#opts.cwd + 2) -- +2 to remove the trailing slash
      end
      -- Remove './' prefix and append '/' suffix
      local clean_entry = relative_path:gsub('^%./', '') .. '/'
      return {
        value = entry,
        display = clean_entry,
        ordinal = clean_entry,
      }
    end,
  })

  local previewer = previewers.new_buffer_previewer({
    title = function()
      -- TODO: show condensed cwd
      -- TODO: write helper function that accepts abs path and prettifies it
      return 'in: ' .. opts.cwd
    end,
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
        vim.api.nvim_set_hl(0, 'TelescopePreviewDirectory', { fg = tc.foam })
      end)
    end,
  })

  pickers
    .new(opts, {
      prompt_title = 'Find Directories',
      initial_mode = 'insert',
      finder = finder,
      debounce = 100, -- for performance / less spam
      previewer = previewer,
      sorter = config_values.generic_sorter({}),
    })
    :find()
end

return find_dirs
