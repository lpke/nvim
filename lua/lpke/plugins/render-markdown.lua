local function config()
  local render_markdown = require('render-markdown')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  helpers.set_hl('RenderMarkdownCode', { bg = tc.surface })

  render_markdown.setup({
    file_types = { 'markdown', 'Avante' },
    completions = { lsp = { enabled = true } },
    code = {
      language_icon = false,
      language_name = false,
      border = 'hide',
    },
  })
end

return {
  'MeanderingProgrammer/render-markdown.nvim',
  config = config,
}
