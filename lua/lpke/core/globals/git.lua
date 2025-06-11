-- TODO
function Lpke_path_git_root() end

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
