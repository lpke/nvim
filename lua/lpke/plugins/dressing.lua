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

    select = {
      builtin = {
        override = function(conf)
          -- Dressing's statuscolumn padding consumes one display column, so
          -- content-fitted select windows need one extra column to avoid truncation.
          conf.width = conf.width + 1
          return conf
        end,
      },
      get_config = function(opts)
        if opts.kind == 'lpke.codecompanion.acp_resume' then
          return {
            backend = { 'builtin' },
            builtin = {
              max_width = { 240, 0.98 },
              min_width = { 80, 0.5 },
              override = function(conf)
                local max_width = math.max(1, vim.o.columns - 4)
                conf.width = math.min(conf.width + 1, max_width)
                conf.col =
                  math.max(0, math.floor((vim.o.columns - conf.width) / 2))
                return conf
              end,
              win_options = {
                wrap = false,
                list = true,
                listchars = 'extends:>',
              },
            },
          }
        end

        if opts.kind == 'codecompanion.nvim' then
          return {
            backend = { 'builtin' },
          }
        end
      end,
    },
  })
end

return {
  'stevearc/dressing.nvim',
  commit = '2d7c2db2507fa3c4956142ee607431ddb2828639',
  event = 'VeryLazy',
  config = config,
}
