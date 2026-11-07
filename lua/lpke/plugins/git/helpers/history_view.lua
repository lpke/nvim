local M = {}

-- Diffview's log stream supplies commit metadata, but its file parser splits
-- paths on tabs and leaves Git's quoted filenames intact. Reuse the state's
-- NUL-delimited reader for each commit's files, keeping the native history UI.
function M.configure(view, spec)
  require('lpke.plugins.git.helpers.state_view').configure(view, spec)
  local adapter = view.adapter
  local async = require('diffview.async')
  local RevType = require('diffview.vcs.rev').RevType
  local LogEntry = require('diffview.vcs.log_entry').LogEntry
  adapter.parse_fh_data = function(self, data, commit, state)
    local left = data.left_hash and self.Rev(RevType.COMMIT, data.left_hash)
      or self.Rev.new_null_tree()
    local right = state.prepared_log_opts.base
      or self.Rev(RevType.COMMIT, data.right_hash)
    local args = self:rev_to_args(left, right)
    args[#args + 1] = '--'
    local literal = ':(top,literal)'
    local follow = state.single_file and state.log_options.follow
      and #state.path_args == 1
      and state.path_args[1]:sub(1, #literal) == literal
    local path
    if follow then
      path = (state.old_path or state.path_args[1]):sub(#literal + 1)
      -- Filtering Git's diff to only the new name turns a rename into an
      -- addition. Read the complete rename-aware delta, then select this file
      -- using its literal bytes. Advance its old name for earlier commits.
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
      for _, file in ipairs(files) do
        if file.path == path and file.oldpath then
          state.old_path = literal .. file.oldpath
        end
      end
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
