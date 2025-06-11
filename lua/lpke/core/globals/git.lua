-- find the git root of any path (if applicable)
function Lpke_find_git_root(path)
  -- Handle nil or empty path
  if not path or path == '' then
    return nil
  end

  -- Convert to absolute path and get directory
  local current_path = vim.fn.fnamemodify(path, ':p')
  if vim.fn.isdirectory(current_path) == 0 then
    current_path = vim.fn.fnamemodify(current_path, ':h')
  end

  -- Traverse up the directory tree
  while current_path and current_path ~= '/' do
    local git_dir = current_path .. '/.git'
    if vim.fn.isdirectory(git_dir) == 1 then
      return current_path
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
