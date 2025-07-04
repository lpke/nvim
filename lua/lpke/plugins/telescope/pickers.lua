local actions = require('telescope.actions')
local builtin = require('telescope.builtin')
local helpers = require('lpke.core.helpers')
local tc = Lpke_theme_colors

local E = {}

-- custom pickers
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

function E.find_directories_oil()
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local action_state = require('telescope.actions.state')
  local previewers = require('telescope.previewers')

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
      initial_mode = 'insert',
      finder = finders.new_oneshot_job({
        'find',
        '.',
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
          return {
            value = entry,
            display = entry,
            ordinal = entry,
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
      attach_mappings = function(prompt_bufnr, _map)
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

function E.smart_find_files()
  if vim.bo.filetype == 'oil' then
    E.find_directories_oil()
  else
    builtin.find_files()
  end
end

return E
