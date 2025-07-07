local function config()
  local render_markdown = require('render-markdown')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  helpers.set_hl('RenderMarkdownBullet', { fg = tc.muted })

  -- https://github.com/MeanderingProgrammer/render-markdown.nvim#setup
  render_markdown.setup({
    file_types = { 'markdown', 'help', 'codecompanion' },
    completions = { lsp = { enabled = true } },
    heading = {
      position = 'inline',
      icons = { '', '', '', '', '', '' },
      backgrounds = {
        'none',
        'none',
        'none',
        'none',
        'none',
        'none',
      },
    },
    bullet = {
      icons = { '', '', '', '' },
    },
    code = {
      language_icon = false,
      language_name = false,
      border = 'thick',
    },
    sign = {
      enabled = false,
    }
  })
end

return {
  'MeanderingProgrammer/render-markdown.nvim',
  config = config,
}
