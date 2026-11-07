local M = {}

-- Keep the native history UI, with complete metadata and literal file readers.
function M.configure(view, spec)
  local state_view = require('lpke.plugins.git.helpers.state_view')
  state_view.configure(view, spec)
  local adapter = view.adapter
  local async = require('diffview.async')
  local utils = require('diffview.utils')
  local RevType = require('diffview.vcs.rev').RevType
  local LogEntry = require('diffview.vcs.log_entry').LogEntry
  require('lpke.plugins.git.helpers.readonly_view').configure(view, 'History')
  -- Navigation can arrive while the initial history file is still loading.
  -- Native layouts reuse Window.file across awaits; serialize selections so a
  -- pending reader cannot resume against another entry's buffer.
  local selection = require('diffview.control').Semaphore(1)
  local set_file = view._set_file
  view._set_file = async.void(function(self, ...)
    local permit = async.await(selection:acquire())
    local ok, err = async.pawait(set_file, self, ...)
    permit:forget()
    if not ok then
      error(err)
    end
  end)
  local run = async.wrap(function(self, args, callback)
    vim.system(
      utils.vec_join({ self:bin() }, self:args(), args),
      { cwd = self.ctx.toplevel },
      vim.schedule_wrap(callback)
    )
  end)
  adapter.stream_fh_data = function(self, state)
    local stream = require('diffview.stream').AsyncListStream()
    local status = require('diffview.vcs.utils').JobStatus
    local finished, process = false, nil
    stream:on_close(function(shutdown)
      if shutdown and shutdown:check() and not finished then
        process:kill(15)
      end
    end)
    -- The pinned plugin stops reading its job's pipes at process exit, before
    -- stdout necessarily reaches EOF. vim.system drains both pipes first.
    -- Metadata needs no numstat: scoped file reads below own the comparisons.
    local format = table.concat(
      { '%H', '%P', '%an', '%at', '%ai', '%ar', '%D', '%gd', '%s' },
      '%x00'
    )
    process = vim.system(
      utils.vec_join(
        { self:bin() },
        self:args(),
        {
          'log',
          '-z',
          '--no-patch',
          '--no-color',
          '--no-show-signature',
          '--no-ext-diff',
          '--no-textconv',
          '--format=' .. format,
        },
        state.prepared_log_opts.flags,
        state.prepared_log_opts.rev_range,
        { '--' },
        state.path_args
      ),
      { cwd = self.ctx.toplevel },
      vim.schedule_wrap(function(result)
        finished = true
        if stream:is_closed() then
          return
        end
        if result.code ~= 0 then
          stream:push({ status.ERROR, nil, result.stderr })
          stream:close()
          return
        end
        local fields = vim.split(result.stdout, '\0', { plain = true })
        if fields[#fields] == '' then
          table.remove(fields)
        end
        if #fields % 9 ~= 0 then
          stream:push({ status.ERROR, nil, 'Incomplete Git history metadata' })
          stream:close()
          return
        end
        for i = 1, #fields, 9 do
          local data = {
            right_hash = fields[i],
            left_hash = fields[i + 1]:match('^(%x+)'),
            author = fields[i + 2],
            time = tonumber(fields[i + 3]),
            time_offset = fields[i + 4]:match('([+-]%d%d%d%d)$'),
            rel_date = fields[i + 5],
            ref_names = fields[i + 6],
            reflog_selector = fields[i + 7],
            subject = fields[i + 8],
            valid = true,
          }
          if
            not data.time
            or not data.time_offset
            or not data.right_hash:match('^%x+$')
          then
            stream:push({ status.ERROR, nil, 'Invalid Git history metadata' })
            stream:close()
            return
          end
          stream:push({ status.PROGRESS, data })
        end
        stream:push({ status.SUCCESS })
        stream:close()
      end)
    )
    return stream
  end
  local empty_tree
  adapter.parse_fh_data = function(self, data, commit, state)
    if not data.left_hash and not empty_tree then
      empty_tree = state_view.empty_tree_oid(self)
    end
    local left = self.Rev(RevType.COMMIT, data.left_hash or empty_tree)
    local right = state.prepared_log_opts.base
      or self.Rev(RevType.COMMIT, data.right_hash)
    local args = self:rev_to_args(left, right)
    args[#args + 1] = '--'
    local literal = ':(top,literal)'
    local follow = state.single_file
      and state.log_options.follow
      and #state.path_args == 1
      and state.path_args[1]:sub(1, #literal) == literal
    local path
    if follow then
      path = (state.old_path or state.path_args[1]):sub(#literal + 1)
      -- Filtering Git's diff to only the new name turns a rename into an
      -- addition. Discover this file's old name using the same focused log as
      -- preflight; unrestricted numstat would require excluded blob contents.
      local result = async.await(run(self, {
        'log',
        '--format=',
        '--name-status',
        '-z',
        '--follow',
        '--diff-merges=first-parent',
        '--no-ext-diff',
        '--no-textconv',
        data.right_hash .. '^!',
        '--',
        literal .. path,
      }))
      if result.code ~= 0 then
        error(result.stderr)
      end
      args[#args + 1] = literal .. path
      local records = vim.split(result.stdout, '\0', { plain = true })
      local i = 1
      while i < #records do
        local status = records[i]:gsub('^\n+', '')
        local old, new = records[i + 1], records[i + 2]
        if status:match('^[RC]%d+$') then
          if new == path then
            args[#args + 1] = literal .. old
            state.old_path = literal .. old
          end
          i = i + 3
        else
          i = i + 2
        end
      end
      table.insert(args, 1, '--find-renames')
    else
      vim.list_extend(args, state.path_args)
    end
    local err, files = async.await(
      self:tracked_files(left, right, args, 'working', state.layout_opt)
    )
    if err then
      error(table.concat(err, '\n'))
    end
    if follow then
      files = vim.tbl_filter(function(file)
        return file.path == path or file.oldpath == path
      end, files)
    end
    for _, file in ipairs(files) do
      file.commit = commit
      for _, side in ipairs(file.layout:files()) do
        side.commit = commit
      end
    end
    local options = {
      path_args = state.path_args,
      commit = commit,
      files = files,
      single_file = state.single_file,
    }
    if #files == 0 then
      if #state.path_args > 0 then
        return false, 'No relevant file data for the literal history path'
      end
      return true, LogEntry.new_null_entry(self, options)
    end
    return true, LogEntry(options)
  end
end

return M
