local function config()
  local mason = require('mason') -- package manager
  local mason_lspconfig = require('mason-lspconfig') -- for lsps
  local mason_tool_installer = require('mason-tool-installer') -- for other tools

  local lsp_settings = require('lpke.lsp')
  local language_servers = lsp_settings.enabled_language_servers
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  mason.setup({
    ui = {
      icons = {
        package_installed = '●',
        package_pending = '○',
        package_uninstalled = '✖',
      },
    },
  })

  mason_lspconfig.setup({
    -- set in my lsp settings
    ensure_installed = language_servers,
    -- If enabled: runs `vim.lsp.enable(<server>)` using lspconfig
    -- I prefer to control this explicitly inside my lspconfig.lua
    automatic_enable = false,
  })

  -- See `:Mason` for list of installed tools and their target filetypes
  mason_tool_installer.setup({
    ensure_installed = {
      -- linters
      'pylint', -- python
      -- formatters
      'prettier', -- html/css/js/ts/json/md/graphql
      'stylua', -- lua
      'shfmt', -- bash/shell
      'isort', -- python imports
      'black', -- python formatting
    },
  })

  -- theme
  helpers.set_hl('MasonHeader', { fg = tc.base, bg = tc.gold })
  helpers.set_hl('MasonHighlightBlockBold', { link = 'Visual' })
  helpers.set_hl('MasonHighlightBlockBoldSecondary', { link = 'Visual' })
  helpers.set_hl('MasonHighlightSecondary', { fg = tc.gold })
  helpers.set_hl('MasonMutedBlock', { link = 'CursorLine' })
  helpers.set_hl('MasonMutedBlockBold', { link = 'CursorLine' })
  helpers.set_hl('MasonHighlight', { fg = tc.growth })
  helpers.set_hl('MasonMuted', { fg = tc.muted })
  helpers.set_hl('MasonHeaderSecondary', { link = 'Visual' })
  helpers.set_hl('MasonHighlightBlock', { fg = tc.base, bg = tc.growth })

  -- keymaps
  helpers.keymap_set_multi({
    { 'nC', '<BS>im', 'Mason', { desc = 'Open Mason GUI' } },
  })
end

return {
  'mason-org/mason.nvim',
  dependencies = {
    'mason-org/mason-lspconfig.nvim',
    'WhoIsSethDaniel/mason-tool-installer.nvim',
  },
  config = config,
}
