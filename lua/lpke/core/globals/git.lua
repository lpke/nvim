local helpers = require('lpke.core.helpers')

-- find the git root of any path, or current file (if applicable)
function Lpke_find_git_root(path)
  -- Handle nil or empty path - use current buffer's path
  if not path or path == '' then
    path = vim.api.nvim_buf_get_name(0)
    if vim.bo.filetype == 'oil' then
      path = path:gsub('^oil://', '')
    end
    if path == '' then
      return nil -- Current buffer has no file
    end
  end

  -- Convert to absolute path and get directory
  local current_path = vim.fn.fnamemodify(path, ':p')
  if vim.fn.isdirectory(current_path) == 0 then
    current_path = vim.fn.fnamemodify(current_path, ':h')
  end

  -- Traverse up the directory tree
  while current_path and current_path ~= '/' do
    local git_dir = current_path .. '/.git'
    -- check if .git is a directory (most cases)
    if vim.fn.isdirectory(git_dir) == 1 then
      return current_path
    -- check if .git is a file (worktrees)
    elseif vim.fn.filereadable(git_dir) == 1 then
      local git_file_content = vim.fn.readfile(git_dir)[1]
      if git_file_content and git_file_content:match('^gitdir: ') then
        return current_path
      end
    end

    -- Move to parent directory
    local parent = vim.fn.fnamemodify(current_path, ':h')
    if parent == current_path then
      break -- Reached filesystem root
    end
    current_path = parent
  end

  return nil
end

-- print the git root
function Lpke_git_root(path)
  print(Lpke_find_git_root(path))
end

-- open a new tab with 2 left/right windows, each with a seperate new buffer that has bufhidden=wipe and nomodified and buftype=nofile
function Lpke_diff()
  vim.cmd('tabnew')
  vim.bo.bufhidden = 'wipe'
  vim.bo.modified = false
  vim.bo.buftype = 'nofile'
  vim.api.nvim_buf_set_name(0, 'Temp File 2')

  vim.cmd('vsplit')
  vim.cmd('enew')
  vim.bo.bufhidden = 'wipe'
  vim.bo.modified = false
  vim.bo.buftype = 'nofile'
  vim.api.nvim_buf_set_name(0, 'Temp File 1')

  vim.cmd('windo diffthis')
  vim.cmd('wincmd H')

  vim.schedule(function()
    vim.cmd('windo set wrap')
    vim.cmd('wincmd h')
  end)
end

-- returns a string of the git handler or nil if not a git buffer
---@param bufnr integer|nil
---@return 'git'|'fugitive'|'diffview'|'gitsigns'|nil
function Lpke_git_buf(bufnr)
  if not bufnr then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local buf_name = helpers.get_buf_name(bufnr)
  local file_type = helpers.get_file_type(bufnr)

  local git_buffer = vim.tbl_contains(
    { 'git', 'gitcommit', 'gitui', 'gitmerge', 'gitrebase' },
    file_type
  ) or string.match(buf_name, '^git://') or string.match(buf_name, '^git://')
  local fugitive_buffer = string.match(file_type, 'fugitive')
    or string.match(buf_name, '^fugitive://')
  local diffview_buffer = string.match(file_type, 'Diffview')
    or string.match(buf_name, '^diffview://')
  local gitsigns_buffer = string.match(file_type, 'gitsigns')
    or string.match(buf_name, '^gitsigns%-.+://')

  if git_buffer then
    return 'git'
  elseif fugitive_buffer then
    return 'fugitive'
  elseif diffview_buffer then
    return 'diffview'
  elseif gitsigns_buffer then
    return 'gitsigns'
  end
  return nil
end
