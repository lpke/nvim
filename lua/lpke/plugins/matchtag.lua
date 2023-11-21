local function config()
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- stylua: ignore start
  -- theme
  helpers.set_hl('matchTag', { link = 'Visual' })
  helpers.set_hl('matchTagError', { bg = tc.lovebg })

  helpers.keymap_set_multi({
    { 'nC', '<F2>%', 'MatchTagToggle', { desc = 'Toggle highlight matching HTML tags' } },
  })
  -- stylua: ignore end

  -- options
  vim.g.vim_matchtag_enable_by_default = 0
  vim.g.vim_matchtag_highlight_cursor_on = 1
  vim.g.vim_matchtag_timeout = 50
  vim.g.vim_matchtag_disable_cache = 0
  vim.g.vim_matchtag_debug = 0
  vim.g.vim_matchtag_files = '*.html,*.xml,*.js,*.jsx,*.ts,*.tsx,*.vue,*.svelte'
  vim.g.vim_matchtag_skip = [[javascript\|css\|script\|style]]
  vim.g.vim_matchtag_skip_except = [[html\|template]]
end

return {
  'leafOfTree/vim-matchtag',
  event = 'VeryLazy',
  config = config,
}
