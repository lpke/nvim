-- TODO: write this custom picker

local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local sorters = require('telescope.sorters')
local previewers = require('telescope.previewers')
-- local make_entry = require('telescope.make_entry')
-- local config_values = require('telescope.config').values

local tc = Lpke_theme_colors

-- TODO: change back to local variable after testing/complete
find_dirs = function(opts)
  opts = opts or {}
  opts.cwd = opts.cwd or vim.fn.getcwd(-1, -1)

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

  local finder = finders.new_oneshot_job({
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
  })

  local previewer = previewers.new_buffer_previewer({
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
      sorter = sorters.highlighter_only(opts), -- highlight in results
    })
    :find()
end

return find_dirs
