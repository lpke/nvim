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
  helpers.set_hl_multi({
    ['@none'] = { fg = tc.textminus },
    ['@number'] = { fg = tc.irisminus },
    ['@constant.builtin'] = { fg = tc.love },
    ['@constructor'] = { fg = tc.growth },
    ['@property'] = { italic = false, fg = tc.foam },
    ['@function.builtin'] = { italic = false, fg = tc.love },
    ['@lsp.typemod.function.defaultLibrary.lua'] = { link = '@function.builtin' },
    ['@variable'] = { italic = false, fg = tc.text },
    ['@variable.builtin'] = { fg = tc.love, italic = false, bold = false },
    ['@module.builtin'] = { bold = false },
    ['@parameter'] = { italic = false, fg = tc.iris },
    ['@variable.parameter'] = { link = '@parameter' },
    ['@keyword'] = { link = 'Keyword' },
    ['@keyword.import'] = { link = 'Keyword' },
    ['@keyword.conditional'] = { link = 'Keyword' },
    ['@keyword.conditional.ternary'] = { fg = tc.pine, italic = false },
    ['@keyword.repeat'] = { link = 'Keyword' },
    ['@keyword.exception'] = { link = 'Keyword' },
    ['@keyword.return'] = { link = 'Keyword' },
    ['@include'] = { link = 'Keyword' },
    ['@type'] = { link = 'Type' },
    ['@type.builtin'] = { link = 'Type' },
    ['@type.builtin.typescript'] = { link = 'Type' },
    ['@tag'] = { link = 'Tag' },
    ['@tag.tsx'] = { link = 'Tag' }, -- custom components
    ['@tag.builtin.tsx'] = { fg = tc.growthminus }, -- html elements
    ['@tag.builtin.javascript'] = { fg = tc.growthminus }, -- html elements
    ['@tag.attribute'] = { fg = tc.iris, italic = true },
    ['@markup.heading.gitcommit'] = { fg = tc.foam, bold = false },
    ['@markup.list'] = { fg = tc.muted },
    -- tsx/jsx/html fixes (simplify)
    ['@markup.heading.1.tsx'] = { link = '@spell' },
    ['@markup.heading.2.tsx'] = { link = '@spell' },
    ['@markup.heading.3.tsx'] = { link = '@spell' },
    ['@markup.heading.4.tsx'] = { link = '@spell' },
    ['@markup.heading.5.tsx'] = { link = '@spell' },
    ['@markup.heading.6.tsx'] = { link = '@spell' },
    ['@markup.link.label.tsx'] = { link = '@spell' },
    ['@markup.italic.tsx'] = { link = '@spell' },
    ['@markup.strong.tsx'] = { link = '@spell' },
    ['@markup.raw.tsx'] = { link = '@spell' },
    ['@markup.heading.1.javascript'] = { link = '@spell' },
    ['@markup.heading.2.javascript'] = { link = '@spell' },
    ['@markup.heading.3.javascript'] = { link = '@spell' },
    ['@markup.heading.4.javascript'] = { link = '@spell' },
    ['@markup.heading.5.javascript'] = { link = '@spell' },
    ['@markup.heading.6.javascript'] = { link = '@spell' },
    ['@markup.link.label.javascript'] = { link = '@spell' },
    ['@markup.italic.javascript'] = { link = '@spell' },
    ['@markup.strong.javascript'] = { link = '@spell' },
    ['@markup.raw.javascript'] = { link = '@spell' },
    ['@markup.heading.1.html'] = { link = '@spell' },
    ['@markup.heading.2.html'] = { link = '@spell' },
    ['@markup.heading.3.html'] = { link = '@spell' },
    ['@markup.heading.4.html'] = { link = '@spell' },
    ['@markup.heading.5.html'] = { link = '@spell' },
    ['@markup.heading.6.html'] = { link = '@spell' },
    ['@markup.link.label.html'] = { link = '@spell' },
    ['@markup.italic.html'] = { link = '@spell' },
    ['@markup.strong.html'] = { link = '@spell' },
    ['@markup.raw.html'] = { link = '@spell' },
  })


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
