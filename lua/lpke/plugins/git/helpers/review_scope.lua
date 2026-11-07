local M = {}
local uv = vim.uv
local utils = require('diffview.utils')

-- Query top-level literal prefixes so an index file replacing a selected
-- parent is visible too. Siblings are inspected but never become action paths.
function M.path_scope(paths)
  local selected, ancestors, queries, seen = {}, {}, {}, {}
  for _, path in ipairs(paths) do
    assert(type(path) == 'string' and path ~= '' and not path:find('%z'))
    selected[path] = true
    local parts = vim.split(path, '/', { plain = true })
    local parent = ''
    for i, part in ipairs(parts) do
      assert(part ~= '.' and part ~= '..' and part ~= '', 'Invalid review path')
      parent = parent == '' and part or parent .. '/' .. part
      if i < #parts then
        ancestors[parent] = true
      end
    end
    if not seen[parts[1]] then
      seen[parts[1]], queries[#queries + 1] = true, parts[1]
    end
  end
  return {
    queries = queries,
    includes = function(path)
      if selected[path] then
        return true
      end
      local message = 'Refresh the review: a selected file boundary changed'
      assert(not ancestors[path], message)
      local parent = path:match('^(.*)/[^/]+$')
      while parent do
        assert(not selected[parent], message)
        parent = parent:match('^(.*)/[^/]+$')
      end
      return false
    end,
  }
end

-- Literal pathspecs still recurse. Check both Git namespaces and filesystem
-- boundaries immediately before a live action, rather than trusting the panel.
function M.validate(adapter, paths, command)
  local root = adapter.ctx.toplevel
  local scope, gitlinks = M.path_scope(paths), {}
  for _, path in ipairs(paths) do
    local parent = root
    local parts = vim.split(path, '/', { plain = true })
    for i, part in ipairs(parts) do
      assert(part ~= '.' and part ~= '..' and part ~= '', 'Invalid review path')
      if i < #parts then
        parent = parent .. '/' .. part
        local stat = uv.fs_lstat(parent)
        assert(not stat or stat.type == 'directory', 'Changed parent boundary')
      end
    end
  end
  local function git(args, optional)
    local result = vim
      .system(
        utils.vec_join(adapter:get_command(), {
          '--literal-pathspecs',
        }, args),
        { cwd = root }
      )
      :wait()
    assert(optional or result.code == 0, result.stderr)
    return result
  end
  local function inspect(records, tree)
    for record in records:gmatch('([^%z]+)%z') do
      local mode, path
      if tree then
        mode, path = record:match('^(%d+) %w+ %x+\t(.*)$')
      else
        mode, path = record:match('^(%d+) %x+ %d+\t(.*)$')
      end
      assert(mode, 'Unrecognized Git file entry')
      if scope.includes(path) and mode == '160000' then
        gitlinks[path] = true
      end
    end
  end
  inspect(
    git(utils.vec_join({ 'ls-files', '--stage', '-z', '--' }, scope.queries)).stdout
  )
  local target
  if command == 'reset' then
    local head = git({ 'rev-parse', '--verify', '--quiet', 'HEAD' }, true)
    if head.code == 0 then
      target = vim.trim(head.stdout)
      inspect(
        git(utils.vec_join({ 'ls-tree', '-rz', target, '--' }, scope.queries)).stdout,
        true
      )
    else
      assert(head.code == 1, head.stderr)
      target = false
    end
  end
  if command ~= 'reset' then
    for _, path in ipairs(paths) do
      local stat = uv.fs_lstat(root .. '/' .. path)
      assert(
        not stat
          or stat.type == 'file'
          or stat.type == 'link'
          or (stat.type == 'directory' and gitlinks[path]),
        'Changed worktree boundary'
      )
    end
  end
  return target
end

return M
