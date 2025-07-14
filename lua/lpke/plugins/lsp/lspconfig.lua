Lpke_diagnostic_config = {
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = '■',
      [vim.diagnostic.severity.WARN] = '▲',
      [vim.diagnostic.severity.INFO] = '◆',
      [vim.diagnostic.severity.HINT] = '●',
    },
  },
  virtual_text = {
    prefix = '■',
    virt_text_pos = 'eol_right_align',
  },
  float = {
    border = 'rounded',
  },
  -- ensure that signs are sorted in sign column (errors on top)
  severity_sort = true,
}

local function config()
  local lsp_settings = require('lpke.lsp')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  local cmp_nvim_lsp = require('cmp_nvim_lsp')

  -- theme (see functions for the rest)
  helpers.set_hl_multi({
    ['LspInfoTitle'] = { fg = tc.growth },
    ['DiagnosticOk'] = { fg = tc.growth },
    ['DiagnosticSignOk'] = { fg = tc.growth },
    ['DiagnosticFloatingOk'] = { fg = tc.growth },
  })
  Lpke_show_diagnostic_virtual_text()
  Lpke_hide_diagnostic_hl()

  -- config options (:h diagnostic.opts)
  vim.diagnostic.config(Lpke_diagnostic_config)

  -- diagnostics filter
  local function filter_diagnostics(diag) -- diag.source, diag.message, diag.code
    -- current line diagnostics (not including `diag`) - TODO: no longer needed?
    -- local ldiag =
    --   vim.diagnostic.get(0, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 })

    -- lua
    if string.match(diag.source, '^[Ll]ua.*') then
      if string.match(diag.message, 'Unused local `_.+`.') then
        return false
      end
    end

    -- typescript - TODO: no longer needed?
    -- if diag.source == 'typescript' then
    --   local esldiag = helpers.arr_filter((ldiag or {}), function(item)
    --     if type(item) ~= 'table' then
    --       return false
    --     end
    --     return item.source == 'eslint_d' -- deprecated: `eslint_d` linter replaced with `eslint-lsp` (mason)
    --   end)
    --
    --   -- handle TS/eslint diagnostic double-ups
    --   if #esldiag > 0 then
    --     -- unused variables
    --     if diag.code == 6133 then
    --       return false
    --     end
    --   end
    -- end

    return true
  end

  local global_handlers = {
    ['textDocument/publishDiagnostics'] = function(_, result, ctx)
      helpers.arr_filter_inplace(result.diagnostics, filter_diagnostics) -- custom part
      vim.lsp.diagnostic.on_publish_diagnostics(_, result, ctx) -- default part (fixed signature)
    end,
  }

  local global_capabilities = cmp_nvim_lsp.default_capabilities()

  -- enable each server with my config overrides (if provided) and globals (above)
  for language_server, config_override in pairs(lsp_settings.config_overrides) do
    local merged_config = vim.tbl_deep_extend(
      'force',
      { handlers = global_handlers, capabilities = global_capabilities },
      config_override
    )

    vim.lsp.config(language_server, merged_config)
    vim.lsp.enable(language_server)
  end

  -- LSP hover overrides
  local hover = vim.lsp.buf.hover
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.lsp.buf.hover = function()
    hover({
      border = 'rounded',
    })
  end

  -- LSP diagnostic overrides
  local diagnostic_open_float = vim.diagnostic.open_float
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.diagnostic.open_float = function(opts)
    diagnostic_open_float(
      vim.tbl_deep_extend('force', { border = 'rounded' }, opts or {})
    )
  end

  -- stylua: ignore start
  -- keymaps
  helpers.keymap_set_multi({
    -- remove defaults introduced in nvim 0.11
    -- https://gpanders.com/blog/whats-new-in-neovim-0-11/#more-default-mappings
    { 'nD', 'grn', '' },
    { 'nD', 'grr', '' },
    { 'nD', 'gri', '' },
    { 'nvD', 'gra', '' },

    -- info/toggle/reload
    { 'nC', '<BS>ip', 'LspInfo', { desc = 'Open LSP info window' } },
    { 'nv', '<F2>d', Lpke_toggle_diagnostics, { desc = 'Toggle diagnostics visibility' }},
    { 'nv', '<A-d>', Lpke_toggle_diagnostics, { desc = 'Toggle diagnostics visibility' }},
    { 'nv', '<F2>v', Lpke_toggle_virtual_text, { desc = 'Toggle virtual text for current line only' }},
    { 'nv', '<A-v>', Lpke_toggle_virtual_text, { desc = 'Toggle virtual text for current line only' }},
    { 'nv', '<F2>e', Lpke_toggle_virtual_text_current_line, { desc = 'Toggle virtual text for current line only' }},
    { 'nv', '<A-e>', Lpke_toggle_virtual_text_current_line, { desc = 'Toggle virtual text for current line only' }},
    { 'nv', '<F2>t', Lpke_toggle_dim_virtual_text, { desc = 'Toggle diagnostics virtual text brightness' }},
    { 'nv', '<A-t>', Lpke_toggle_dim_virtual_text, { desc = 'Toggle diagnostics virtual text brightness' }},
    { 'nv', '<F2>V', Lpke_toggle_diagnostics_hl, { desc = 'Toggle diagnostics highlighting' }},
    { 'nv', '<A-V>', Lpke_toggle_diagnostics_hl, { desc = 'Toggle diagnostics highlighting' }},
    { 'n', '<leader>R', Lpke_lsp_restart, { desc = 'Restart LSPs for current buffer filetype' }},

    -- smart actions
    { 'n', 'gr', vim.lsp.buf.rename, { desc = 'Smart rename' } },
    { 'nv', 'ga', vim.lsp.buf.code_action, { desc = 'See available code actions' }, },

    -- hover info
    { 'n', 'gh', vim.lsp.buf.hover, { desc = 'Show documentation for what is under cursor' } },
    { 'n', 'gl', vim.diagnostic.open_float, { desc = 'Show line diagnostics' } },

    -- 'l'sp navigation
    { 'nC', '<leader>l', 'Telescope diagnostics bufnr=0', { desc = 'Show buffer diagnostics' }, },
    { 'n', '[l', function() vim.diagnostic.jump({ count = -1, float = true }) end, { square_repeat = true, desc = 'Go to previous diagnostic' }, },
    { 'n', ']l', function() vim.diagnostic.jump({ count = 1, float = true }) end, { square_repeat = true, desc = 'Go to next diagnostic' }, },

    -- jump/list related code
    { 'nC', '<leader>;', 'Telescope lsp_references', { desc = 'Show LSP references' }, },
    { 'nC', 'gd', 'Telescope lsp_definitions', { desc = 'Show LSP definitions' }, },
    { 'nC', 'gt', 'Telescope lsp_type_definitions', { desc = 'Show LSP type definitions' }, },
    { 'nC', 'gi', 'Telescope lsp_implementations', { desc = 'Show LSP implementations' }, },
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
