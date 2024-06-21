local function config()
  local mason = require('mason') -- package manager
  local mason_lspconfig = require('mason-lspconfig') -- lsp config module
  -- manages third-party tools such as prettier
  local mason_tool_installer = require('mason-tool-installer')
  local tc = Lpke_theme_colors
  local helpers = require('lpke.core.helpers')

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
    ensure_installed = {
      'html',
      'cssls',
      'tailwindcss',
      'tsserver',
      'jsonls',
      'graphql',
      'lua_ls',
      'emmet_ls',
      'bashls',
      'pyright',
    },
    automatic_installation = true,
  })

  mason_tool_installer.setup({
    ensure_installed = {
      'prettier',
      'eslint-lsp', -- (updated from `eslint_d`)
      'stylua', -- lua formatter
      'isort', -- python formatter
      'black', -- python formatter
      'pylint', -- python linter
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
    {'nC', '<BS>im', 'Mason', { desc = 'Open Mason GUI' }},
  })

end


return {
  'williamboman/mason.nvim',
  dependencies = {
    'williamboman/mason-lspconfig.nvim',
    'WhoIsSethDaniel/mason-tool-installer.nvim',
  },
  config = config,
}
