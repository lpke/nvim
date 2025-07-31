-- disable next line auto-comment
vim.cmd('autocmd FileType * set formatoptions-=cro')

-- toggle diagnostics when going enter/leave insert mode
Lpke_diagnostics_insert_disabled = nil
vim.api.nvim_create_autocmd('InsertEnter', {
  pattern = '*',
  callback = function()
    Lpke_diagnostics_insert_disabled = true
    Lpke_toggle_diagnostics(false)
  end,
})
vim.api.nvim_create_autocmd('InsertLeave', {
  pattern = '*',
  callback = function()
    if Lpke_diagnostics_insert_disabled then
      Lpke_toggle_diagnostics(Lpke_diagnostics_enabled_prev)
      Lpke_diagnostics_insert_disabled = false
    end
  end,
})

-- remember folds
vim.api.nvim_create_autocmd({ 'BufWinLeave' }, {
  pattern = { '*.*' },
  desc = 'Save view (folds) when closing file',
  command = 'mkview',
})
vim.api.nvim_create_autocmd({ 'BufWinEnter' }, {
  pattern = { '*.*' },
  desc = 'load view (folds) when opening file',
  command = 'silent! loadview',
})
