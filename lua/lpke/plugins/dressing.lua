local function config()
  local dressing = require('dressing')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  helpers.set_hl('DressingTitle', {
    bg = tc.surface,
    fg = tc.subtle,
  })

  dressing.setup({
    input = {
      title_pos = 'center',
      insert_only = false, -- allow normal mode inside inputs
      start_in_insert = true,
      win_options = {
        -- override highlights for dressing windows only
        winhighlight = 'FloatTitle:DressingTitle',
      },
    },

    mappings = {
      n = {
        ['<Esc>'] = 'Close',
        ['<CR>'] = 'Confirm',
      },
      i = {
        ['<C-c>'] = 'Close',
        ['<CR>'] = 'Confirm',
        ['<Up>'] = 'HistoryPrev',
        ['<Down>'] = 'HistoryNext',
      },
    },

    nui = {
      position = '0%', -- appears at start of cursor pos
    },
  })
end

return {
  'stevearc/dressing.nvim',
  event = 'VeryLazy',
  config = config,
}
