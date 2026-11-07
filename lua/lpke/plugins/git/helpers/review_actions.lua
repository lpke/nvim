local M = {}

-- Expand panel directory requests into represented files. Git's literal path
-- mode still recurses through directories, so passing a directory is too broad.
function M.configure(view, spec)
  local adapter = view.adapter
  local async = require('diffview.async')
  local utils = require('diffview.utils')
  local literal = require('lpke.plugins.git.helpers.state_view').literal_paths
  local function entries(staged)
    if staged then
      return spec.state == 'staged' and view.files.working or view.files.staged
    end
    if spec.state == 'staged' then
      return {}
    end
    return utils.vec_join(view.files.working, view.files.conflicting)
  end
  local function scope(paths, staged)
    local requested = {}
    for _, path in ipairs(paths or {}) do
      requested[path:gsub('/+$', '')] = true
    end
    local function selected(path)
      if paths == nil or requested['.'] then
        return true
      end
      while path do
        if requested[path] then
          return true
        end
        path = path:match('^(.*)/[^/]+$')
      end
      return false
    end
    local result, seen = {}, {}
    local function add(path)
      if path and not seen[path] then
        seen[path], result[#result + 1] = true, path
      end
    end
    for _, entry in ipairs(entries(staged)) do
      if
        selected(entry.path) or (entry.oldpath and selected(entry.oldpath))
      then
        add(entry.path)
        add(entry.oldpath)
      end
    end
    return result
  end
  local function mutate(command, paths)
    if #paths == 0 then
      return true
    end
    local _, code = adapter:exec_sync(
      utils.vec_join({ command, '--' }, literal({ paths = paths })),
      adapter.ctx.toplevel
    )
    return code == 0
  end
  adapter.add_files = function(_, paths)
    return mutate('add', scope(paths or {}, false))
  end
  adapter.reset_files = function(_, paths)
    return mutate('reset', scope(paths, true))
  end

  local function represented(path)
    for _, entry in view.files:iter() do
      if path == entry.path or path == entry.oldpath then
        return entry
      end
    end
    return false
  end
  local function literal_adapter(self)
    return setmetatable({
      get_command = function()
        return utils.vec_join(self:get_command(), { '--literal-pathspecs' })
      end,
    }, { __index = self })
  end
  adapter.file_restore = async.wrap(function(self, path, kind, commit, callback)
    local entry = represented(path)
    if not entry then
      callback(false)
      return
    end
    if entry.kind == 'conflicting' then
      utils.err(
        'Use the conflict resolution actions before restoring this file.'
      )
      callback(false)
      return
    end
    local ok, success, undo = pcall(
      require('lpke.plugins.git.helpers.review_restore').restore,
      self,
      entry,
      kind,
      commit
    )
    if not ok then
      utils.err(success)
      callback(false)
      return
    end
    callback(success, undo)
  end)

  -- Saving an editable index buffer also needs byte-safe index-info framing.
  local stage_index = adapter.stage_index_file
  adapter.stage_index_file = function(self, file)
    if not represented(file.path) then
      return false
    end
    local proxy = literal_adapter(self)
    proxy.exec_sync = function(_, args, options)
      if args[1] == 'ls-files' and args[2] == '--stage' then
        args = { 'ls-files', '--stage', '-z', '--', file.path }
      elseif args[1] == 'update-index' and args[2] == '--index-info' then
        args = { 'update-index', '-z', '--index-info' }
        -- The plugin's line writer appends a newline after its input. Send the
        -- NUL-framed record directly instead, including literal newline paths.
        local result = vim
          .system(utils.vec_join(proxy:get_command(), args), {
            cwd = options.cwd,
            stdin = options.writer .. '\0',
          })
          :wait()
        return vim.split(result.stdout or '', '\n', { trimempty = true }),
          result.code,
          vim.split(result.stderr or '', '\n', { trimempty = true })
      end
      return self.exec_sync(proxy, args, options)
    end
    return stage_index(proxy, file)
  end
end

return M
