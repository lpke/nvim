local M = {}
local uv = vim.uv
local utils = require('diffview.utils')

local function git(root, args, input, allow_failure)
  local result = vim
    .system(utils.vec_join({ 'git', '--literal-pathspecs' }, args), {
      cwd = root,
      stdin = input,
    })
    :wait()
  assert(allow_failure or result.code == 0, result.stderr)
  return result
end

local function safe_path(root, path)
  assert(
    path ~= '' and not path:find('%z') and path:sub(1, 1) ~= '/',
    'Invalid restore path'
  )
  for part in path:gmatch('[^/]+') do
    assert(part ~= '..' and part ~= '.', 'Invalid restore path')
  end
  local current = root
  local parts = vim.split(path, '/', { plain = true })
  for i = 1, #parts - 1 do
    current = current .. '/' .. parts[i]
    local stat = uv.fs_lstat(current)
    assert(
      not stat or stat.type == 'directory',
      'Restore parent is no longer a directory'
    )
  end
  local absolute = root .. '/' .. path
  local parent = vim.fs.dirname(absolute)
  while not uv.fs_lstat(parent) do
    parent = vim.fs.dirname(parent)
  end
  local real = assert(uv.fs_realpath(parent))
  local base = assert(uv.fs_realpath(root))
  assert(
    real == base or real:sub(1, #base + 1) == base .. '/',
    'Restore parent escapes repository'
  )
  return absolute
end

local function index(root, paths)
  local records = git(
    root,
    utils.vec_join({ 'ls-files', '--stage', '-z', '--' }, paths)
  ).stdout
  local result = {}
  for record in records:gmatch('([^%z]+)%z') do
    local mode, oid, stage, path = record:match('^(%d+) (%x+) (%d+)\t(.*)$')
    assert(stage == '0', 'Resolve merge conflicts before restoring this file')
    result[path] = { mode = mode, oid = oid }
  end
  return result
end

local function tree(root, source, paths)
  local records =
    git(root, utils.vec_join({ 'ls-tree', '-z', source, '--' }, paths)).stdout
  local result = {}
  for record in records:gmatch('([^%z]+)%z') do
    local mode, _, oid, path = record:match('^(%d+) (%w+) (%x+)\t(.*)$')
    assert(
      mode and mode ~= '040000' and mode ~= '160000',
      'Review directories in their own checkout'
    )
    result[path] = { mode = mode, oid = oid }
  end
  return result
end

local function unmodified(root, paths)
  for _, path in ipairs(paths) do
    local buf = utils.find_file_buffer(safe_path(root, path))
    assert(
      not buf or not vim.bo[buf].modified,
      'File has unsaved buffer changes'
    )
  end
end

local function backup(root, path)
  local absolute = safe_path(root, path)
  local stat = uv.fs_lstat(absolute)
  local saved = { path = vim.base64.encode(path), kind = 'absent' }
  if not stat then
    return saved
  end
  assert(
    stat.type == 'file' or stat.type == 'link',
    'Review directories in their own checkout'
  )
  local data
  if stat.type == 'link' then
    -- A link's contents are its target text, including broken/directory links.
    -- Never open, hash or read the referenced file.
    data = assert(uv.fs_readlink(absolute))
  else
    local fd = assert(uv.fs_open(absolute, 'r', 0))
    local opened = uv.fs_fstat(fd)
    local valid = opened
      and opened.type == 'file'
      and opened.dev == stat.dev
      and opened.ino == stat.ino
    local ok, value = pcall(function()
      assert(valid, 'File type changed before backup')
      local bytes = assert(uv.fs_read(fd, opened.size, 0))
      assert(#bytes == opened.size, 'File changed during backup')
      return bytes
    end)
    uv.fs_close(fd)
    assert(ok, value)
    data = value
  end
  saved.kind, saved.mode = stat.type, stat.mode % 512
  saved.oid =
    vim.trim(git(root, { 'hash-object', '-w', '--stdin' }, data).stdout)
  return saved
end

local function reload(root, paths)
  for _, path in ipairs(paths) do
    local buf = utils.find_file_buffer(root .. '/' .. path)
    if buf then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd('checktime')
      end)
    end
  end
end

local function undo_command(saved)
  return string.format(
    ':lua require("lpke.plugins.git.helpers.review_restore").undo(%q)',
    vim.base64.encode(vim.json.encode(saved))
  )
end

function M.undo(token)
  local saved = vim.json.decode(vim.base64.decode(token))
  assert(
    saved.version == 1 and saved.host == uv.os_gethostname(),
    'Undo belongs to another host'
  )
  assert(
    saved.oid_length == 40 or saved.oid_length == 64,
    'Invalid saved object format'
  )
  assert(
    type(saved.change_index) == 'boolean'
      and #saved.work >= 1
      and #saved.work <= 2,
    'Invalid saved scope'
  )
  local root, paths, contents = vim.base64.decode(saved.root), {}, {}
  for i, item in ipairs(saved.work) do
    local path = vim.base64.decode(item.path)
    local absolute = safe_path(root, path)
    local stat = uv.fs_lstat(absolute)
    assert(
      not stat or stat.type == 'file' or stat.type == 'link',
      'Undo would replace a directory'
    )
    assert(
      item.kind == 'absent' or item.kind == 'file' or item.kind == 'link',
      'Invalid saved file type'
    )
    paths[i] = path
    if item.kind ~= 'absent' then
      assert(
        type(item.oid) == 'string'
          and item.oid:match('^%x+$')
          and (#item.oid == 40 or #item.oid == 64)
      )
      contents[i] = git(root, { 'cat-file', 'blob', item.oid }).stdout
      assert(
        item.kind ~= 'file'
          or (
            type(item.mode) == 'number'
            and item.mode % 1 == 0
            and item.mode >= 0
            and item.mode <= 511
          )
      )
    end
  end
  unmodified(root, paths)
  index(root, paths) -- Refuse newly introduced conflicts before any write.
  if saved.change_index then
    local records = {}
    for i, path in ipairs(paths) do
      records[#records + 1] = '0 '
        .. string.rep('0', saved.oid_length)
        .. '\t'
        .. path
        .. '\0'
      local previous = saved.index[i]
      if previous and previous ~= vim.NIL then
        assert(
          previous.mode == '100644'
            or previous.mode == '100755'
            or previous.mode == '120000'
            or previous.mode == '160000'
        )
        assert(
          previous.oid:match('^%x+$') and #previous.oid == saved.oid_length
        )
        git(root, { 'cat-file', '-e', previous.oid })
        records[#records + 1] = previous.mode
          .. ' '
          .. previous.oid
          .. '\t'
          .. path
          .. '\0'
      end
    end
    git(root, { 'update-index', '-z', '--index-info' }, table.concat(records))
  end
  for i, item in ipairs(saved.work) do
    local absolute = safe_path(root, paths[i])
    if uv.fs_lstat(absolute) then
      assert(uv.fs_unlink(absolute))
    end
    if item.kind ~= 'absent' then
      vim.fn.mkdir(vim.fs.dirname(absolute), 'p')
      if item.kind == 'link' then
        assert(uv.fs_symlink(contents[i], absolute))
      else
        local fd = assert(uv.fs_open(absolute, 'wx', item.mode))
        local ok, err = uv.fs_write(fd, contents[i], 0)
        uv.fs_close(fd)
        assert(ok == #contents[i], err or 'Incomplete undo write')
        assert(uv.fs_chmod(absolute, item.mode))
      end
    end
  end
  reload(root, paths)
end

function M.restore(adapter, entry, kind, commit)
  local root, paths = adapter.ctx.toplevel, { entry.path }
  if entry.oldpath then
    paths[#paths + 1] = entry.oldpath
  end
  unmodified(root, paths)
  local before = index(root, paths)
  local source = commit or (kind == 'staged' and 'HEAD' or nil)
  if
    source == 'HEAD'
    and git(root, { 'rev-parse', '--verify', 'HEAD' }, nil, true).code ~= 0
  then
    source =
      require('lpke.plugins.git.helpers.state_view').empty_tree_oid(adapter)
  end
  local target = source and tree(root, source, paths) or before
  local checked = {}
  for _, values in ipairs({ target, before }) do
    for _, value in pairs(values) do
      assert(value.mode ~= '160000', 'Review directories in their own checkout')
      if not checked[value.oid] then
        git(root, { 'cat-file', '-e', value.oid })
        checked[value.oid] = true
      end
    end
  end
  local saved = {
    version = 1,
    host = uv.os_gethostname(),
    root = vim.base64.encode(root),
    work = {},
    index = {},
    change_index = source ~= nil,
    oid_length = #require('lpke.plugins.git.helpers.state_view').empty_tree_oid(
      adapter
    ),
  }
  local git_paths, remove = {}, {}
  for i, path in ipairs(paths) do
    saved.work[i], saved.index[i] = backup(root, path), before[path] or vim.NIL
    if target[path] or before[path] then
      git_paths[#git_paths + 1] = path
    else
      remove[#remove + 1] = path
    end
  end
  local undo = undo_command(saved)
  local args = { 'restore', '--worktree' }
  if source then
    vim.list_extend(args, { '--source=' .. source, '--staged' })
  end
  vim.list_extend(args, utils.vec_join({ '--' }, git_paths))
  local ok, err = pcall(function()
    if #git_paths > 0 then
      git(root, args)
    end
    for _, path in ipairs(remove) do
      local absolute = safe_path(root, path)
      if uv.fs_lstat(absolute) then
        assert(uv.fs_unlink(absolute))
      end
    end
  end)
  if not ok then
    local rolled_back = pcall(M.undo, vim.base64.encode(vim.json.encode(saved)))
    error(
      tostring(err)
        .. (
          rolled_back and '\nPrevious state restored.'
          or '\nUndo with ' .. undo
        )
    )
  end
  reload(root, paths)
  return true, undo
end

return M
