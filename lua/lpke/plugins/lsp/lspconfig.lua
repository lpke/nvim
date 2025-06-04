function Lpke_toggle_diagnostics()
  return
end

local function config()
  local lsp_settings = require('lpke.lsp')
  local helpers = require('lpke.core.helpers')

  -- enable each server with my config overrides (if provided)
  for language_server, config_override in pairs(lsp_settings.config_overrides) do
    vim.lsp.config(language_server, config_override)
    vim.lsp.enable(language_server)
  end

  -- stylua: ignore start
  helpers.keymap_set_multi({
    -- info/toggle/reload
    { 'nC', '<BS>ip', 'LspInfo', { desc = 'Open LSP info window' } },
    -- {'nv', '<F2>d', Lpke_toggle_diagnostics, { desc = 'Toggle diagnostics visibility globally' }},
    -- {'nv', '<A-d>', Lpke_toggle_diagnostics, { desc = 'Toggle diagnostics visibility globally' }},
    -- {'nv', '<F2>v', Lpke_toggle_diagnostics_virtual_text, { desc = 'Toggle diagnostics virtual text brightness globally' }},
    -- {'nv', '<A-v>', Lpke_toggle_diagnostics_virtual_text, { desc = 'Toggle diagnostics virtual text brightness globally' }},
    -- {'nv', '<F2>V', Lpke_toggle_diagnostics_hl, { desc = 'Toggle diagnostics highlighting globally' }},
    -- {'nv', '<A-V>', Lpke_toggle_diagnostics_hl, { desc = 'Toggle diagnostics highlighting globally' }},
    -- {'nC', '<leader>R', 'LspRestart', { desc = 'Restart LSP' }},

    -- smart actions
    { 'n', 'gr', vim.lsp.buf.rename, { desc = 'Smart rename' } },
    { 'nv', '<leader>a', vim.lsp.buf.code_action, { desc = 'See available code actions' }, },

    -- hover info
    { 'n', 'gh', function() vim.lsp.buf.hover({ border = 'rounded' }) end, { desc = 'Show documentation for what is under cursor' }, },
    { 'n', 'gl', function() vim.diagnostic.open_float({ border = 'rounded' }) end, { desc = 'Show line diagnostics' }, },

    -- 'l'sp navigation
    { 'nC', '<leader>l', 'Telescope diagnostics bufnr=0', { desc = 'Show buffer diagnostics' }, },
    { 'n', '[l', function() vim.diagnostic.jump({ count = -1, float = true }) end, { desc = 'Go to previous diagnostic' }, },
    { 'n', ']l', function() vim.diagnostic.jump({ count = 1, float = true }) end, { desc = 'Go to next diagnostic' }, },

    -- jump/list related code
    { 'nC', '<leader>;', 'Telescope lsp_references', { desc = 'Show LSP references' }, },
    { 'nC', 'gd', 'Telescope lsp_definitions', { desc = 'Show LSP definitions' }, },
    { 'nC', 'gt', 'Telescope lsp_type_definitions', { desc = 'Show LSP type definitions' }, },
    { 'nC', 'gi', 'Telescope lsp_implementations', { desc = 'Show LSP implementations' }, },
    { 'n', 'gD', vim.lsp.buf.declaration, { desc = 'Go to declaration' } },
  })
  -- stylua: ignore end
end

return {
  'neovim/nvim-lspconfig',
  event = { 'BufReadPre', 'BufNewFile' },
  dependencies = {
    'hrsh7th/cmp-nvim-lsp', -- completions
  },
  config = config,
}
