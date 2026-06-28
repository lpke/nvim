-- Neovim's markdown ftplugin enables `formatoptions+=tc`, which hard-wraps text
-- and comment-like lines during insert mode when `textwidth` is non-zero. Keep
-- `textwidth` for manual formatting commands, but disable typing-time breaks.
vim.opt_local.formatoptions:remove({ 't', 'c' })

vim.opt_local.tabstop = 2
vim.opt_local.softtabstop = 2
vim.opt_local.shiftwidth = 2
