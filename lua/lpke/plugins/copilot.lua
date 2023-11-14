local function config()
  local copilot = require('copilot')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- theme
  helpers.set_hl('CopilotAnnotation', { fg = tc.mutedminus })

  copilot.setup({
    panel = {
      enabled = true,
      auto_refresh = false,
      keymap = {
        jump_prev = '[[',
        jump_next = ']]',
        accept = '<CR>',
        refresh = 'gr',
        open = '<F2>/',
      },
      layout = {
        position = 'bottom', -- | top | left | right
        ratio = 0.4,
      },
    },
    suggestion = {
      enabled = true,
      auto_trigger = false,
      debounce = 75,
      keymap = {
        accept = '<F2>;',
        accept_word = false,
        accept_line = false,
        next = '<F2>.',
        prev = '<F2>>',
        dismiss = '<F2>c',
      },
    },
    filetypes = {
      yaml = false,
      markdown = false,
      help = false,
      gitcommit = false,
      gitrebase = false,
      hgcommit = false,
      svn = false,
      cvs = false,
      oil = false,
      fugitive = false,
      ['.'] = false,
    },
    copilot_node_command = 'node', -- Node.js version must be > 18.x
    server_opts_overrides = {},
  })
end

return {
  'zbirenbaum/copilot.lua',
  event = 'InsertEnter',
  config = config,
}
