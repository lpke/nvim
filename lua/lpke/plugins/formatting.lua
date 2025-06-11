local function config()
  local conform = require('conform')
  local helpers = require('lpke.core.helpers')

  conform.setup({
    -- Formatters are installed by Mason (see `:Mason`)
    formatters_by_ft = {
      javascript = { 'prettier' },
      typescript = { 'prettier' },
      javascriptreact = { 'prettier' },
      typescriptreact = { 'prettier' },
      svelte = { 'prettier' },
      css = { 'prettier' },
      html = { 'prettier' },
      json = { 'prettier' },
      yaml = { 'prettier' },
      markdown = { 'prettier' },
      graphql = { 'prettier' },
      lua = { 'stylua' },
      python = { 'isort', 'black' },
      sh = { 'shfmt' },
      bash = { 'shfmt' },
      zsh = { 'shfmt' },
    },
  })

  -- keymaps
  local function format()
    conform.format({ lsp_fallback = true, async = false, timeout_ms = 2000 })
  end
  helpers.keymap_set_multi({
    { 'nv', '==', format, { desc = 'Format file' } },
    { 'nC', '<BS>ic', 'ConformInfo', { desc = 'Open conform info GUI' } },
  })
end

return {
  'stevearc/conform.nvim',
  lazy = true,
  event = { 'BufReadPre', 'BufNewFile' },
  config = config,
}
