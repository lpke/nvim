local M = {}
local uv = vim.uv
local utils = require('diffview.utils')

-- Literal pathspecs still recurse. Check both Git namespaces and filesystem
-- boundaries immediately before a live action, rather than trusting the panel.
function M.validate(adapter, paths, command)
  local root = adapter.ctx.toplevel
  local selected, gitlinks = {}, {}
  for _, path in ipairs(paths) do
    assert(path ~= '' and path:sub(1, 1) ~= '/' and not path:find('%z'))
    selected[path] = true
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
      assert(mode and selected[path], 'Changed index or reset-target boundary')
      if mode == '160000' then
        gitlinks[path] = true
      end
    end
  end
  inspect(
    git(utils.vec_join({ 'ls-files', '--stage', '-z', '--' }, paths)).stdout
  )
  local target
  if command == 'reset' then
    local head = git({ 'rev-parse', '--verify', '--quiet', 'HEAD' }, true)
    if head.code == 0 then
      target = vim.trim(head.stdout)
      inspect(
        git(utils.vec_join({ 'ls-tree', '-rz', target, '--' }, paths)).stdout,
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
