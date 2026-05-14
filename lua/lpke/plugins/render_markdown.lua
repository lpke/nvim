local function refresh_lualine()
  pcall(function()
    require('lualine').refresh()
  end)
end

local function current_or_buf(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

function Lpke_render_markdown_active(bufnr)
  bufnr = current_or_buf(bufnr)
  local ok, manager = pcall(require, 'render-markdown.core.manager')
  return ok and manager.attached(bufnr)
end

function Lpke_render_markdown_enabled(bufnr)
  bufnr = current_or_buf(bufnr)
  if not Lpke_render_markdown_active(bufnr) then
    return false
  end

  local ok, state = pcall(require, 'render-markdown.state')
  if not ok then
    return false
  end

  local got_config, config = pcall(state.get, bufnr)
  return got_config and config.enabled == true
end

function Lpke_toggle_render_markdown()
  if not Lpke_render_markdown_active(0) then
    return
  end

  require('render-markdown').buf_toggle()
  refresh_lualine()
end

local function config()
  local render_markdown = require('render-markdown')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  helpers.set_hl('RenderMarkdownBullet', { fg = tc.muted })

  -- https://github.com/MeanderingProgrammer/render-markdown.nvim#setup
  render_markdown.setup({
    file_types = { 'markdown', 'help', 'codecompanion' },
    render_modes = true,
    completions = { lsp = { enabled = true } },
    on = {
      attach = function(ctx)
        helpers.keymap_set({
          'nv',
          '<A-m>',
          Lpke_toggle_render_markdown,
          {
            buffer = ctx.buf,
            desc = 'Render Markdown: Toggle buffer rendering',
          },
        })
        refresh_lualine()
      end,
    },
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
    },
  })
end

return {
  'MeanderingProgrammer/render-markdown.nvim',
  config = config,
}
