local function config()
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- stylua: ignore start
  -- theme
  helpers.set_hl('UndotreeNode', { fg = tc.gold })
  helpers.set_hl('UndotreeBranch', { fg = tc.goldfaded })
  helpers.set_hl('UndotreeCurrent', { fg = tc.foam })
  helpers.set_hl('UndotreeNext', { fg = tc.pine })
  helpers.set_hl('UndotreeTimestamp', { link = 'Comment' })
  helpers.set_hl('UndotreeSavedBig', { fg = tc.love, bold = true })
  helpers.set_hl('UndotreeSavedSmall', { fg = tc.love })
  -- stylua: ignore end

  helpers.keymap_set_multi({
    { 'nC', '<leader>u', 'UndotreeToggle', { desc = 'Undotree: Open undo tree' } },
  })

  -- options
  vim.g.undotree_SetFocusWhenToggle = 1
  vim.g.undotree_ShortIndicators = 1
  vim.g.undotree_HelpLine = 0
  vim.g.undotree_TreeNodeShape = '●'
  vim.g.undotree_TreeVertShape = '│'
  vim.g.undotree_TreeSplitShape = '╱'
  vim.g.undotree_TreeReturnShape = '╲'
end

return {
  'mbbill/undotree',
  lazy = false,
  config = config,
}
