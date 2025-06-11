-- TODO
function Lpke_path_git_root() end

-- open a new tab with 2 left/right windows, each with a seperate new buffer that has bufhidden=wipe and nomodified and buftype=nofile
function Lpke_diff()
  vim.cmd('tabnew')
  vim.bo.bufhidden = 'wipe'
  vim.bo.modified = false
  vim.bo.buftype = 'nofile'
  vim.api.nvim_buf_set_name(0, 'Temp File 2')
  -- FIXME
  vim.wo.wrap = true

  vim.cmd('vsplit')
  vim.cmd('enew')
  vim.bo.bufhidden = 'wipe'
  vim.bo.modified = false
  vim.bo.buftype = 'nofile'
  vim.api.nvim_buf_set_name(0, 'Temp File 1')
  -- FIXME
  vim.wo.wrap = true

  vim.cmd('windo diffthis')
  vim.cmd('wincmd H')
end
