local function config()
  local helpers = require('lpke.core.helpers')
  local ts_install = require('nvim-treesitter.install')
  local ts_configs = require('nvim-treesitter.configs')
  local tc = Lpke_theme_colors

  -- update/install parsers
  pcall(ts_install.update({ with_sync = true }))
  ts_install.compilers = { 'clang' }
  helpers.clear_last_message('All parsers are up-to-date!') -- clear annoying message on startup

  ts_configs.setup({
    -- stylua: ignore start
    ensure_installed = {
      'vimdoc', 'vim', 'luadoc', 'lua', 'javascript', 'jsdoc', 'typescript',
      'html', 'css', 'json', 'jsonc', 'yaml', 'graphql', 'bash', 'gitignore',
      'gitcommit', 'gitattributes', 'git_rebase', 'git_config', 'yaml', 'toml',
      'markdown', 'python', 'rust', 'c', 'c_sharp', 'cpp', 'regex'
    },
    -- stylua: ignore end
    sync_install = false, -- install parsers synchronously
    auto_install = true, -- automatically install missing parsers when entering buffer
    highlight = {
      enable = true,
      disable = {},

      -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
      -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
      -- Using this option may slow down your editor, and you may see some duplicate highlights.
      -- Instead of true it can also be a list of languages
      additional_vim_regex_highlighting = false,
    },
    indent = {
      enable = true,
      disable = {},
    },
    autopairs = {
      enable = true,
    },
  })

  -- stylua: ignore start
  -- highlight customisations (top-level groups found in rose-pine config file)
  helpers.set_hl('@none', { fg = tc.textminus })
  helpers.set_hl('@number', { fg = tc.irisminus })
  helpers.set_hl('@constant.builtin', { fg = tc.love })
  helpers.set_hl('@constructor', { fg = tc.growth })
  helpers.set_hl('@property', { italic = false, fg = tc.foam })
  helpers.set_hl('@function.builtin', { italic = false, fg = tc.love })
  helpers.set_hl('@lsp.typemod.function.defaultLibrary.lua', { link = '@function.builtin' })
  helpers.set_hl('@variable', { italic = false, fg = tc.text })
  helpers.set_hl('@parameter', { italic = false, fg = tc.iris })
  helpers.set_hl('@variable.parameter', { link = '@parameter' })
  helpers.set_hl('@keyword', { link = 'Keyword' })
  helpers.set_hl('@keyword.import', { link = 'Keyword' })
  helpers.set_hl('@keyword.conditional', { link = 'Keyword' })
  helpers.set_hl('@keyword.conditional.ternary', { fg = tc.pine, italic = false })
  helpers.set_hl('@keyword.repeat', { link = 'Keyword' })
  helpers.set_hl('@keyword.exception', { link = 'Keyword' })
  helpers.set_hl('@keyword.return', { link = 'Keyword' })
  helpers.set_hl('@include', { link = 'Keyword' })
  helpers.set_hl('@type', { link = 'Type' })
  helpers.set_hl('@type.builtin', { link = 'Type' })
  helpers.set_hl('@type.builtin.typescript', { link = 'Type' })
  helpers.set_hl('@tag', { link = 'Tag' })
  helpers.set_hl('@tag.tsx', { link = 'Tag' }) -- custom components
  helpers.set_hl('@tag.builtin.tsx', { fg = tc.growthminus }) -- html elements
  helpers.set_hl('@tag.attribute', { fg = tc.iris, italic = true })

  helpers.keymap_set_multi({
    {'nC', '<leader>t', 'Inspect', { desc = 'Treesitter: Inspect highlight group under cursor (:Inspect)' }},
    {'nC', '<leader>T', 'InspectTree', { desc = 'Treesitter: Open parsed syntax tree (:InspectTree)' }},
  })
  -- stylua: ignore end

  -- filetype customisation
  vim.treesitter.language.register('markdown', 'mdx')
end

return {
  'nvim-treesitter/nvim-treesitter',
  dependencies = {
    'nvim-treesitter/nvim-treesitter-textobjects',
  },
  config = config,
}
