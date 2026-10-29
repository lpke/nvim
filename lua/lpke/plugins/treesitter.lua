local function config()
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- update/install parsers, then enable highlighting and indentation
  -- stylua: ignore start
  require('lpke.plugins.helpers.treesitter').setup({
    'vimdoc', 'vim', 'luadoc', 'lua', 'javascript', 'jsdoc', 'typescript',
    'html', 'css', 'json', 'yaml', 'graphql', 'bash', 'gitignore',
    'gitcommit', 'gitattributes', 'git_rebase', 'git_config', 'toml',
    'markdown', 'markdown_inline', 'python', 'rust', 'c', 'c_sharp', 'cpp',
    'regex'
  })
  -- stylua: ignore end

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
  branch = 'main',
  commit = 'a2f694478be07f89c2d03cc17858a8745a400c4b',
  lazy = false,
  dependencies = {
    {
      'nvim-treesitter/nvim-treesitter-textobjects',
      branch = 'main',
      commit = '5c7b0263797dfd1bd6202f2b219f3b53a80b2187',
    },
  },
  config = config,
}
