local function config()
  local web_devicons = require('nvim-web-devicons')

  -- override the default icon (if enabled)
  -- web_devicons.set_default_icon('', '#6d8086', 65)

  web_devicons.setup({
    default = false, -- fall back on a default icon
    color_icons = true, -- false makes all icons have same color
    variant = nil, -- nil (automatic) | 'light' | 'dark'

    override = {
      -- zsh = {
      --   icon = '',
      --   color = '#428850',
      --   cterm_color = '65',
      --   name = 'Zsh',
      -- },
    },

    -- globally enable "strict" selection of icons - icon will be looked up in
    -- different tables, first by filename, and if not found by extension; this
    -- prevents cases when file doesn't have any extension but still gets some icon
    -- because its name happened to match some extension (default to false)
    strict = true,

    override_by_filename = { -- requires `strict = true`
      -- ['.gitignore'] = {
      --   icon = '',
      --   color = '#f1502f',
      --   name = 'Gitignore',
      -- },
    },
    override_by_extension = { -- requires `strict = true`
      -- ['log'] = {
      --   icon = '',
      --   color = '#81e043',
      --   name = 'Log',
      -- },
    },
    override_by_operating_system = { -- requires `strict = true`
      -- ['apple'] = {
      --   icon = '',
      --   color = '#A2AAAD',
      --   cterm_color = '248',
      --   name = 'Apple',
      -- },
    },
  })
end

return {
  'nvim-tree/nvim-web-devicons',
  config = config,
}
