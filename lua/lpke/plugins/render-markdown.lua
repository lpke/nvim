local function config()
  local render_markdown = require('render-markdown')
  local helpers = require('lpke.core.helpers')
  -- local tc = Lpke_theme_colors

  -- make background match hover box colour (makes other places less slick though)
  -- helpers.set_hl('RenderMarkdownCode', { bg = tc.surface })

  helpers.set_hl('RenderMarkdownH1Bg', { bg = 'none' })
  helpers.set_hl('RenderMarkdownH2Bg', { bg = 'none' })
  helpers.set_hl('RenderMarkdownH3Bg', { bg = 'none' })
  helpers.set_hl('RenderMarkdownH4Bg', { bg = 'none' })
  helpers.set_hl('RenderMarkdownH5Bg', { bg = 'none' })
  helpers.set_hl('RenderMarkdownH6Bg', { bg = 'none' })

  render_markdown.setup({
    file_types = { 'markdown', 'help', 'Avante' },
    completions = { lsp = { enabled = true } },
    code = {
      language_icon = false,
      language_name = false,
      border = 'thick',
    },
  })
end

return {
  'MeanderingProgrammer/render-markdown.nvim',
  config = config,
}
