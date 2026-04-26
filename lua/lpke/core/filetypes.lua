-- mdx
vim.filetype.add({
  extension = {
    mdx = 'mdx',
  },
})

-- handle chezmoi templates
vim.filetype.add({
  filename = {
    ['dot_zshrc.tmpl'] = 'zsh',
    ['dot_zshenv.tmpl'] = 'zsh',
    ['dot_gitconfig.tmpl'] = 'gitconfig',
  },
  pattern = {
    -- *.<filetype>.tmpl -> <filetype>
    ['.*%.(%a+)%.tmpl'] = function(_, _, ext)
      return ext
    end,
  },
})
