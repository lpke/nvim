local caveman = require('lpke.plugins.ai.helpers.caveman')

return {
  ['caveman'] = {
    description = 'Toggle caveman response mode for HTTP adapters',
    enabled = function(opts)
      local adapter = opts and opts.adapter
      return type(adapter) == 'table' and adapter.type == 'http'
    end,
    callback = function(chat)
      caveman.slash(chat)
    end,
    opts = {
      contains_code = false,
    },
  },
  ['image'] = {
    opts = {
      dirs = {
        vim.fn.expand('~/Pictures'),
        vim.fn.expand('~/Screenshots'),
        vim.fn.expand('~/Downloads'),
        vim.fn.expand('~/Videos'),
      },
    },
  },
  ['git_files_list'] = {
    description = 'List git files (not their contents)',
    callback = function(chat)
      local handle = io.popen('git ls-files')
      if handle ~= nil then
        local result = handle:read('*a')
        handle:close()
        local file_count = #vim.split(vim.trim(result), '\n')
        chat:add_context(
          { role = 'user', content = result },
          'git',
          '<git-files-list files="' .. file_count .. '" />'
        )
      else
        return vim.notify(
          'No git files available',
          vim.log.levels.INFO,
          { title = 'CodeCompanion' }
        )
      end
    end,
    opts = {
      contains_code = false,
    },
  },
  -- vibe-coded. Be careful...
  ['external_files'] = {
    description = 'Add an external directory as context (files outside cwd)',
    callback = function(chat)
      local function add_dir_context(dir)
        if not dir or dir == '' then
          return
        end
        dir = vim.fn.expand(dir)
        dir = vim.fs.normalize(dir)
        if vim.fn.isdirectory(dir) ~= 1 then
          return vim.notify(
            'Not a valid directory: ' .. dir,
            vim.log.levels.ERROR,
            { title = 'CodeCompanion' }
          )
        end
        -- list files in the directory (respecting .gitignore if in a git repo)
        local files_output
        local git_check = vim.fn.system(
          'git -C '
            .. vim.fn.shellescape(dir)
            .. ' rev-parse --is-inside-work-tree 2>/dev/null'
        )
        if vim.v.shell_error == 0 and git_check:match('true') then
          files_output = vim.fn.system(
            'git -C ' .. vim.fn.shellescape(dir) .. ' ls-files'
          )
        else
          files_output = vim.fn.system(
            'find '
              .. vim.fn.shellescape(dir)
              .. ' -type f -not -path "*/.*" | head -500'
          )
        end
        local context_content = string.format(
          'The user has given you access to an additional directory outside the current working directory.\n'
            .. 'External directory: %s\n\n'
            .. 'You can use absolute paths to read, edit, create, and search files in this directory.\n'
            .. 'Files in this directory:\n```\n%s```',
          dir,
          files_output or '(could not list files)'
        )
        chat:add_context(
          { role = 'user', content = context_content },
          'directory',
          '<external-files>' .. dir .. '</external-files>'
        )
        vim.notify(
          'Added external directory: ' .. dir,
          vim.log.levels.INFO,
          { title = 'CodeCompanion' }
        )
      end

      local function pick_with_input()
        vim.ui.input(
          { prompt = 'Directory path: ', completion = 'dir' },
          add_dir_context
        )
      end

      local function pick_with_telescope()
        local actions = require('telescope.actions')
        local action_state = require('telescope.actions.state')
        local pickers = require('telescope.pickers')
        local finders = require('telescope.finders')
        local config_values = require('telescope.config').values

        local home = vim.fn.expand('~')
        pickers
          .new({}, {
            prompt_title = '/external_files - Select Directory',
            cwd = home,
            finder = finders.new_oneshot_job({
              'fd',
              '--type',
              'd',
              '--hidden',
              '--exclude',
              '.git',
              '--exclude',
              'node_modules',
            }, { cwd = home }),
            sorter = config_values.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
              actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then
                  local selected = vim.fs.joinpath(home, entry.value)
                  add_dir_context(selected)
                end
              end)
              return true
            end,
          })
          :find()
      end

      vim.ui.select(
        { 'Telescope picker', 'Absolute path input' },
        { prompt = '/external_files - Choose method:' },
        function(choice)
          if choice == 'Telescope picker' then
            pick_with_telescope()
          elseif choice == 'Absolute path input' then
            pick_with_input()
          end
        end
      )
    end,
    opts = {
      contains_code = false,
    },
  },
  ['git_commit_logs'] = {
    description = 'Add recent git commit messages and metadata to context',
    callback = function(chat)
      vim.ui.input(
        { prompt = 'Number of commits (default 20): ' },
        function(input)
          if input == nil then
            return
          end
          local cleaned = vim.trim(input):gsub('^%((.-)%)$', '%1')
          local count = tonumber(cleaned)
          if not count or count < 1 then
            count = 20
          end
          local cmd = string.format(
            'git log -n %d --pretty=format:"%%h %%ai %%an %%d %%s"',
            count
          )
          local handle = io.popen(cmd)
          if not handle then
            return vim.notify(
              'Failed to run git log',
              vim.log.levels.ERROR,
              { title = 'CodeCompanion' }
            )
          end
          local result = handle:read('*a')
          handle:close()
          if not result or result == '' then
            return vim.notify(
              'No git commits found',
              vim.log.levels.INFO,
              { title = 'CodeCompanion' }
            )
          end
          local content = string.format(
            'Recent git commits (last %d):\n```\n%s\n```',
            count,
            result
          )
          chat:add_context(
            { role = 'user', content = content },
            'git',
            '<git-commit-logs commits="' .. count .. '" />'
          )
          vim.notify(
            string.format('Added %d git commits to context', count),
            vim.log.levels.INFO,
            { title = 'CodeCompanion' }
          )
        end
      )
    end,
    opts = {
      contains_code = false,
    },
  },
  ['git_commit_history'] = {
    description = 'Add full diffs for recent git commits',
    callback = function(chat)
      vim.ui.input(
        { prompt = 'Number of commits with diffs (default 5): ' },
        function(input)
          if input == nil then
            return
          end
          local cleaned =
            vim.trim(input):gsub('^%((.-)%)$', '%1')
          local count = tonumber(cleaned)
          if not count or count < 1 then
            count = 5
          end

          -- Get the last N commit hashes
          local log_cmd = string.format(
            'git log -n %d --pretty=format:"%%H"',
            count
          )
          local log_handle = io.popen(log_cmd)
          if not log_handle then
            return vim.notify(
              'Failed to run git log',
              vim.log.levels.ERROR,
              { title = 'CodeCompanion' }
            )
          end
          local hashes_raw = log_handle:read('*a')
          log_handle:close()
          local hashes =
            vim.split(vim.trim(hashes_raw), '\n')
          if
            #hashes == 0
            or (hashes[1] == '' and #hashes == 1)
          then
            return vim.notify(
              'No git commits found',
              vim.log.levels.INFO,
              { title = 'CodeCompanion' }
            )
          end

          -- Build full diffs for each commit
          local parts = {}
          for i, hash in ipairs(hashes) do
            -- Get commit metadata
            local meta_cmd = string.format(
              'git log -1 --pretty=format:"%%h %%ai %%an %%s" %s',
              hash
            )
            local meta_handle = io.popen(meta_cmd)
            local meta = meta_handle
                and meta_handle:read('*a')
              or ''
            if meta_handle then
              meta_handle:close()
            end

            -- Get full diff for this commit
            local diff_cmd = string.format(
              'git diff %s~1..%s 2>/dev/null',
              hash,
              hash
            )
            local diff_handle = io.popen(diff_cmd)
            local diff = diff_handle
                and diff_handle:read('*a')
              or ''
            if diff_handle then
              diff_handle:close()
            end

            if diff == '' then
              diff =
                '(initial commit or no parent diff available)'
            end

            table.insert(
              parts,
              string.format(
                '--- Commit %d: %s ---\n```diff\n%s\n```',
                i,
                vim.trim(meta),
                vim.trim(diff)
              )
            )
          end

          local content = string.format(
            'Git commit history with full diffs (last %d commits):\n\n%s',
            #hashes,
            table.concat(parts, '\n\n')
          )
          chat:add_context(
            { role = 'user', content = content },
            'git',
            '<git-commit-history versions="'
              .. #hashes
              .. '" />'
          )
          vim.notify(
            string.format(
              'Added %d commits with diffs to context',
              #hashes
            ),
            vim.log.levels.INFO,
            { title = 'CodeCompanion' }
          )
        end
      )
    end,
    opts = {
      contains_code = true,
    },
  },
  ['git_file_history'] = {
    description = 'Add git diffs for a file going back N versions',
    callback = function(chat)
      local actions = require('telescope.actions')
      local action_state = require('telescope.actions.state')
      local pickers = require('telescope.pickers')
      local finders = require('telescope.finders')
      local config_values = require('telescope.config').values

      -- Step 1: Pick a file using telescope (git ls-files)
      local handle = io.popen('git ls-files')
      if not handle then
        return vim.notify(
          'Failed to list git files',
          vim.log.levels.ERROR,
          { title = 'CodeCompanion' }
        )
      end
      local files_raw = handle:read('*a')
      handle:close()
      local files = vim.split(vim.trim(files_raw), '\n')
      if #files == 0 or (files[1] == '' and #files == 1) then
        return vim.notify(
          'No git-tracked files found',
          vim.log.levels.INFO,
          { title = 'CodeCompanion' }
        )
      end

      pickers
        .new({}, {
          prompt_title = '/git_file_history - Select File',
          finder = finders.new_table({ results = files }),
          sorter = config_values.generic_sorter({}),
          attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
              local entry = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              if not entry then
                return
              end
              local selected_file = entry.value

              -- Step 2: Ask how many versions back
              vim.ui.input({
                prompt = 'Versions back for "'
                  .. selected_file
                  .. '" (default 5): ',
              }, function(input)
                if input == nil then
                  return
                end
                local cleaned = vim.trim(input):gsub('^%((.-)%)$', '%1')
                local count = tonumber(cleaned)
                if not count or count < 1 then
                  count = 5
                end

                -- Get the last N commits that touched this file
                local log_cmd = string.format(
                  'git log -n %d --pretty=format:"%%H" -- %s',
                  count,
                  vim.fn.shellescape(selected_file)
                )
                local log_handle = io.popen(log_cmd)
                if not log_handle then
                  return vim.notify(
                    'Failed to get file history',
                    vim.log.levels.ERROR,
                    { title = 'CodeCompanion' }
                  )
                end
                local hashes_raw = log_handle:read('*a')
                log_handle:close()
                local hashes = vim.split(vim.trim(hashes_raw), '\n')
                if
                  #hashes == 0
                  or (hashes[1] == '' and #hashes == 1)
                then
                  return vim.notify(
                    'No history found for ' .. selected_file,
                    vim.log.levels.INFO,
                    { title = 'CodeCompanion' }
                  )
                end

                -- Build diffs for each commit
                local parts = {}
                for i, hash in ipairs(hashes) do
                  -- Get commit metadata
                  local meta_cmd = string.format(
                    'git log -1 --pretty=format:"%%h %%ai %%an %%s" %s',
                    hash
                  )
                  local meta_handle = io.popen(meta_cmd)
                  local meta = meta_handle and meta_handle:read('*a')
                    or ''
                  if meta_handle then
                    meta_handle:close()
                  end

                  -- Get diff for this commit
                  local diff_cmd = string.format(
                    'git diff %s~1..%s -- %s 2>/dev/null',
                    hash,
                    hash,
                    vim.fn.shellescape(selected_file)
                  )
                  local diff_handle = io.popen(diff_cmd)
                  local diff = diff_handle and diff_handle:read('*a')
                    or ''
                  if diff_handle then
                    diff_handle:close()
                  end

                  if diff == '' then
                    diff =
                      '(initial commit or no parent diff available)'
                  end

                  table.insert(
                    parts,
                    string.format(
                      '--- Version %d: %s ---\n```diff\n%s\n```',
                      i,
                      vim.trim(meta),
                      vim.trim(diff)
                    )
                  )
                end

                local content = string.format(
                  'Git file history for `%s` (last %d versions):\n\n%s',
                  selected_file,
                  #hashes,
                  table.concat(parts, '\n\n')
                )
                chat:add_context(
                  { role = 'user', content = content },
                  'git',
                  '<git-file-history versions="'
                    .. #hashes
                    .. '">'
                    .. selected_file
                    .. '</git-file-history>'
                )
                vim.notify(
                  string.format(
                    'Added %d versions of %s to context',
                    #hashes,
                    selected_file
                  ),
                  vim.log.levels.INFO,
                  { title = 'CodeCompanion' }
                )
              end)
            end)
            return true
          end,
        })
        :find()
    end,
    opts = {
      contains_code = true,
    },
  },
}
