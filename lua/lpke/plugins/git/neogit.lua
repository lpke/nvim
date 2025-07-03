local function config()
  local helpers = require('lpke.core.helpers')
  -- local tc = Lpke_theme_colors

  -- stylua: ignore start
  helpers.keymap_set_multi({
    -- {'nv', '<leader>i', function() Lpke_toggle_git_fugitive(true) end, { desc = 'Git: Toggle fugitive window (new tab)' }},
  })
  -- stylua: ignore end
end

return {
  'NeogitOrg/neogit',
  config = config,
  dependencies = {
    'nvim-lua/plenary.nvim', -- required
    'sindrets/diffview.nvim', -- optional - Diff integration
    'nvim-telescope/telescope.nvim', -- optional - Searching
  },
}
