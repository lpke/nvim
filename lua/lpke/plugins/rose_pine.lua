-- Rose Pine Default Palette:
-- https://rosepinetheme.com/palette/ingredients/
--   base = #191724
--   surface = #1f1d2e
--   overlay = #26233a
--   muted = #6e6a86
--   subtle = #908caa
--   text = #e0def4
--   love = #eb6f92
--   gold = #f6c177
--   rose = #ebbcba
--   pine = #31748f
--   foam = #9ccfd8
--   iris = #c4a7e7
--   highlight_low = #21202e
--   highlight_med = #403d52
--   highlight_high = #524f67

-- Grey Shades (ascending brightness order):
--   base | surface | overlay | overlaybump | overlayplus | mutedminus |
--   muted | subtle | subtleplus | textminus | text

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
  -- git
  addbg = '#333c48',
  addbgbright = '#455161',
  changebg = '#433842',
  changebgbright = '#61515f',
  deletebg = '#43293a',
  deletebgbright = '#5e3a52',
}

local function config()
  -- save theme to global var, add extras
  ---@type { base: string, surface: string, overlay: string, muted: string, subtle: string, text: string, love: string, gold: string, rose: string, pine: string, foam: string, iris: string, highlight_low: string, highlight_med: string, highlight_high: string, textminus: string, subtleplus: string, mutedminus: string, mutedplus: string, overlaybump: string, overlayplus: string, growth: string, growthminus: string, irisplus: string, irisminus: string, lovefaded: string, goldfaded: string, irisfaded: string, foamfaded: string, lovebg: string, goldbg: string, irisbg: string, foambg: string, growthbg: string, growthbgplus: string, addbg: string, changebg: string, deletebg: string, addbgbright: string, changebgbright: string, deletebgbright: string }
  Lpke_theme_colors = require('rose-pine.palette')
  for k, v in pairs(ec) do
    Lpke_theme_colors[k] = v
  end

  local tc = Lpke_theme_colors

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
      bold = true,
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

    -- stylua: ignore start
    -- vim highlight groups (inspect under cursor with `:Inspect`)
    highlight_groups = {
      Normal = { bg = 'none' },
      NormalNC = { bg = 'none' },
      VisualNOS = { bg = tc.highlight_med, inherit = false },
      Visual = { bg = tc.highlight_med, inherit = false },
      VertSplit = { bg = 'none', fg = tc.highlight_med },
      WinSeparator = { bg = 'none', fg = tc.highlight_med },
      Comment = { fg = tc.muted },
      ColorColumn = { bg = tc.rose },
      StatusLine = { fg = tc.subtle, bg = tc.overlay },
      StatusLineNC = { fg = tc.subtle, bg = tc.surface },
      EndOfBuffer = { fg = tc.base }, -- remove the `~`
      CursorLine = { bg = 'none' },
      CursorLineNr = { fg = tc.textminus },
      FloatTitle = { fg = tc.subtle, bg = tc.surface },
      TabLineFill = { bg = tc.surface }, -- Non-text area
      TabLine = { fg = tc.subtle, bg = tc.surface }, -- Un-selected tab
      TabLineSel = { fg = tc.textminus, bg = ec.overlaybump, bold = false }, -- Selected tab
      CurSearch = { fg = tc.base, bg = tc.irisplus },
      IncSearch = { link = 'CurSearch' },
      Substitute = { fg = tc.base, bg = tc.love },
      MatchParen = { fg = tc.growth, bg = ec.growthminus, blend = 15 },
      Directory = { bold = false },

      -- vim syntax highlight groups (inherited in treesitter config file for `@` groups)
      Keyword = { fg = tc.pine, italic = true },
      Type = { fg = tc.growth },
      Tag = { fg = tc.growth },
      Structure = { fg = tc.growth },

      -- git overrides
      DiffChange = { force = true, bg = tc.changebg, blend = 100 },
      DiffText = { force = true, bg = tc.changebgbright, blend = 100 },
      GitText = { force = true, bg = tc.changebgbright, blend = 100 },

      -- custom highlight groups
      LpkeTabLineZoom = { fg = tc.irisfaded, bg = tc.surface },
      LpkeTabLineZoomSel = { fg = tc.iris, bg = tc.overlaybump },
      LpkeTabLineMod = { fg = tc.mutedminus, bg = tc.surface, bold = true },
      LpkeTabLineModSel = { fg = tc.subtle, bg = tc.overlaybump, bold = true },
      LpkeTabLineReadonly = { fg = tc.mutedminus, bg = tc.surface },
      LpkeTabLineReadonlySel = { fg = tc.muted, bg = tc.overlaybump },
      LpkeTabLineClose = { fg = tc.overlayplus, bg = tc.surface },
    },
    -- stylua: ignore end
  })

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
