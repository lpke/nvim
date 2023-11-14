local function config()
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- stylua: ignore start
  -- theme
  helpers.set_hl('UndotreeNode', { fg = tc.gold })
  helpers.set_hl('UndotreeBranch', { fg = tc.goldfaded })
  helpers.set_hl('UndotreeCurrent', { fg = tc.foam })
  helpers.set_hl('UndotreeTimestamp', { link = 'Comment' })
  helpers.set_hl('UndotreeSavedBig', { fg = tc.gold, bold = true })
  -- stylua: ignore end

  helpers.keymap_set_multi({
    { 'nC', '<leader>u', 'UndotreeToggle', { desc = 'Undotree: Open undo tree' } },
  })
end

return {
  'mbbill/undotree',
  lazy = false,
  config = config,
}
