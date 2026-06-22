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

local scaffold_backup_suffix = '.scaffold-backup'

vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
  pattern = '*' .. scaffold_backup_suffix,
  callback = function(event)
    local path = event.file
    if not vim.endswith(path, scaffold_backup_suffix) then
      return
    end

    local original_path = path:sub(1, #path - #scaffold_backup_suffix)
    local filetype = vim.filetype.match({
      buf = event.buf,
      filename = original_path,
    })

    if filetype and filetype ~= '' then
      vim.bo[event.buf].filetype = filetype
    end
  end,
})
