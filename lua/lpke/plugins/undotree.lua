local function config()
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- stylua: ignore start
  -- theme
  helpers.set_hl_multi({
    ['UndotreeNode'] = { fg = tc.gold },
    ['UndotreeBranch'] = { fg = tc.goldfaded },
    ['UndotreeCurrent'] = { fg = tc.foam },
    ['UndotreeNext'] = { fg = tc.pine },
    ['UndotreeTimestamp'] = { link = 'Comment' },
    ['UndotreeSavedBig'] = { fg = tc.love, bold = true },
    ['UndotreeSavedSmall'] = { fg = tc.love },
  })

  helpers.keymap_set_multi({
    { 'nC', '<leader>u', 'UndotreeToggle', { desc = 'Undotree: Open undo tree' } },
  })
  -- stylua: ignore end

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
