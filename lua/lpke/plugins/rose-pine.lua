-- palette colors:  https://rosepinetheme.com/palette/ingredients/
-- recipes:         https://github.com/rose-pine/neovim/wiki/Recipes

-- Extra colors
-- Shades: base | surface | overlay | overlaybump | overlayplus | mutedminus | muted | subtle | subtleplus | textminus | text
local ec = {
  textminus = '#c0bcd2',
  subtleplus = '#a7a3bd',
  mutedminus = '#5c5874',
  mutedplus = '#7e799a',
  overlaybump = '#2f2b45',
  overlayplus = '#3c3852',
  growth = '#64a6a5',
  growthminus = '#9fc6c6',
  irisplus = '#dcc2ff',
  irisminus = '#9979c3',
  lovefaded = '#b25774',
  goldfaded = '#ba9360',
  irisfaded = '#9580b2',
  foamfaded = '#789da7',
  lovebg = '#362333',
  goldbg = '#372e30',
  irisbg = '#312b3f',
  foambg = '#2b303d',
  growthbg = '#242b36',
  growthbgplus = '#21373b',
}

local function config()
  require('rose-pine').setup({
    variant = 'main', -- main, moon, dawn
    dark_variant = 'main',
    dim_inactive_windows = false,
    extend_background_behind_borders = true,
    bold_vert_split = false,

    enable = {
      terminal = true,
    },

    styles = {
      bold = false,
      italic = true,
      transparency = false,
    },

    groups = {
      border = 'highlight_med',
      panel = 'surface',
      panel_nc = 'base',

      link = 'iris',
      note = 'pine',
      todo = 'rose',

      hint = 'iris',
      info = 'foam',
      warn = 'gold',
      error = 'love',

      h1 = 'iris',
      h2 = 'foam',
      h3 = 'rose',
      h4 = 'gold',
      h5 = 'pine',
      h6 = 'foam',

      git_add = 'foam',
      git_change = 'rose',
      git_delete = 'love',
      git_dirty = 'rose',
      git_ignore = 'muted',
      git_merge = 'iris',
      git_rename = 'pine',
      git_stage = 'iris',
      git_text = 'rose',
      git_untracked = 'subtle',
    },

    -- vim highlight groups (inspect under cursor with `:Inspect`)
    highlight_groups = {
      Normal = { bg = 'none' },
      NormalNC = { bg = 'none' },
      VertSplit = { bg = 'none' },
      Comment = { fg = 'muted' },
      ColorColumn = { bg = 'rose' },
      StatusLine = { fg = 'subtle', bg = 'overlay' },
      StatusLineNC = { fg = 'subtle', bg = 'surface' },
      EndOfBuffer = { fg = 'base' }, -- remove the `~`
      CursorLine = { bg = 'none' },
      CursorLineNr = { fg = ec.textminus },
      FloatTitle = { fg = 'subtle', bg = 'surface' },
      TabLineFill = { bg = 'surface' }, -- Non-text area
      TabLine = { fg = 'subtle', bg = 'surface' }, -- Un-selected tab
      TabLineSel = { fg = ec.textminus, bg = ec.overlaybump, bold = false }, -- Selected tab
      CurSearch = { fg = 'base', bg = ec.irisplus },
      IncSearch = { link = 'CurSearch' },
      Substitute = { fg = 'base', bg = 'love' },
      MatchParen = { fg = ec.growth, bg = ec.growthminus, blend = 15 },

      -- vim syntax highlight groups (inherited in treesitter config file for `@` groups)
      Keyword = { fg = 'pine', italic = true },
      Type = { fg = ec.growth },
      Tag = { fg = ec.growth },

      -- custom highlight groups
      LpkeTabLineZoom = { fg = ec.irisfaded, bg = 'surface' },
      LpkeTabLineZoomSel = { fg = 'iris', bg = ec.overlaybump },
      LpkeTabLineMod = { fg = ec.mutedminus, bg = 'surface', bold = true },
      LpkeTabLineModSel = { fg = 'subtle', bg = ec.overlaybump, bold = true },
      LpkeTabLineReadonly = { fg = ec.mutedminus, bg = 'surface' },
      LpkeTabLineReadonlySel = { fg = 'muted', bg = ec.overlaybump },
      LpkeTabLineClose = { fg = ec.overlayplus, bg = 'surface' },
    },
  })

  -- save theme to global var, add extras
  Lpke_theme_colors = require('rose-pine.palette')
  for k, v in pairs(ec) do
    Lpke_theme_colors[k] = v
  end

  -- set color scheme
  vim.cmd('colorscheme rose-pine')
end

return {
  'rose-pine/neovim',
  name = 'rose-pine',
  lazy = false,
  priority = 1000,
  config = config,
}
