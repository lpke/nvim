local helpers = require('lpke.core.helpers')

local function config()
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

  -- highlight customisations
  helpers.set_hl('@none', { fg = tc.textminus })
  helpers.set_hl('@variable', { italic = false, fg = tc.text })
  helpers.set_hl('@function.builtin', { italic = false, fg = tc.love })
  helpers.set_hl('@property', { italic = false, fg = tc.foam })
  helpers.set_hl('@parameter', { italic = false, fg = tc.iris })
  helpers.set_hl('@tag.attribute', { italic = true, fg = tc.iris })
  helpers.set_hl('@keyword', { italic = true, fg = tc.pine })
  helpers.set_hl('@include', { italic = true, fg = tc.pine })
  helpers.set_hl('@number', { fg = tc.iris })
  helpers.set_hl('@constructor', { fg = tc.growth })
  helpers.set_hl('@type', { fg = tc.growth })
  helpers.set_hl(
    '@lsp.typemod.function.defaultLibrary.lua',
    { link = '@function.builtin' }
  )

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
