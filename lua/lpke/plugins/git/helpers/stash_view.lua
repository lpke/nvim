local M = {}

function M.open(spec)
  local state = require('lpke.plugins.git.helpers.state_view')
  local async = require('diffview.async')
  local RevType = require('diffview.vcs.rev').RevType
  local DiffView = require('diffview.scene.views.diff.diff_view').DiffView
  local oid = spec.stash_oid
  assert(
    type(oid) == 'string' and (#oid == 40 or #oid == 64) and oid:match('^%x+$'),
    'Stash review requires a full immutable stash OID'
  )
  local root = spec.repo_b64 and vim.base64.decode(spec.repo_b64)
    or vim.uv.cwd()
  local result = vim
    .system({ 'git', '-C', root, 'rev-list', '--parents', '-n', '1', oid })
    :wait()
  assert(result.code == 0, 'Stash object is unavailable: ' .. oid)
  local parents = vim.split(vim.trim(result.stdout), ' ', { plain = true })
  assert(
    #parents == 3 or #parents == 4,
    'Object is not a stash commit: ' .. oid
  )
  local function parent_list(commit)
    local value = vim
      .system({ 'git', '-C', root, 'rev-list', '--parents', '-n', '1', commit })
      :wait()
    assert(value.code == 0, 'Stash parent object is unavailable: ' .. commit)
    return vim.split(vim.trim(value.stdout), ' ', { plain = true })
  end
  local index_parents = parent_list(parents[3])
  assert(
    #index_parents == 2 and index_parents[2] == parents[2],
    'Object is not a stash commit: ' .. oid
  )
  if parents[4] then
    assert(
      #parent_list(parents[4]) == 1,
      'Object is not a stash commit: ' .. oid
    )
  end
  local request = vim.tbl_extend('force', spec, {
    state = 'stash',
    args = { parents[2] .. '..' .. oid },
  })
  return state.open(request, function(view)
    local adapter = view.adapter
    local base = adapter.Rev(RevType.COMMIT, parents[2])
    local saved = adapter.Rev(RevType.COMMIT, oid)
    local index = adapter.Rev(RevType.COMMIT, parents[3])
    local untracked = parents[4] and adapter.Rev(RevType.COMMIT, parents[4])
    local empty = untracked
      and adapter.Rev(RevType.COMMIT, state.empty_tree_oid(adapter))
    -- Use the plugin's per-view file-list hook. Every side is an immutable
    -- commit/tree, including the saved index; no live index buffer is involved.
    view.get_updated_files = async.wrap(function(self, callback)
      local files = require('diffview.vcs.file_dict').FileDict()
      local layouts = {
        default_layout = DiffView.get_default_layout(),
        merge_layout = DiffView.get_default_merge_layout(),
      }
      local function collect(left, right, kind)
        local args = adapter:rev_to_args(left, right)
        vim.list_extend(args, { '--' })
        vim.list_extend(args, self.path_args)
        local err, entries =
          async.await(adapter:tracked_files(left, right, args, kind, layouts))
        if err then
          error(table.concat(err, '\n'))
        end
        return entries
      end
      files:set_working(collect(base, saved, 'working'))
      files:set_staged(collect(base, index, 'staged'))
      if untracked then
        for _, entry in ipairs(collect(empty, untracked, 'working')) do
          entry.status = '?'
          entry.layout.b.file.winbar = ' SAVED UNTRACKED - '
            .. entry.path:gsub('\n', '\\n')
          files.working[#files.working + 1] = entry
        end
      end
      files:update_file_trees()
      callback(nil, files)
    end)
    require('lpke.plugins.git.helpers.readonly_view').configure(view, 'Stash')
  end)
end

return M
