local function config()
  local tscontext = require('treesitter-context')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- theme
  helpers.set_hl('TreesitterContext', { bg = tc.overlay })

  tscontext.setup({
    enable = false,
    max_lines = 6,
    min_window_height = 0, -- 0 for no limit
    line_numbers = true,
    multiline_threshold = 2, -- Maximum number of lines to show for a single context
    trim_scope = 'outer', -- 'inner' or 'outer'
    mode = 'cursor', -- Line used to calculate context. 'cursor' or 'topline'
    -- Separator between context and content. Should be a single character string, like '-'.
    -- When separator is set, the context will only show up when there are at least 2 lines above cursorline.
    separator = nil,
    zindex = 20, -- The Z-index of the context window
    on_attach = nil, -- (fun(buf: integer): boolean) return false to disable attaching
  })

  -- stylua: ignore start
  -- keymaps
  helpers.keymap_set_multi({
    {'n', '<F2>c', function() vim.cmd('TSContextToggle') end, { desc = 'Toggle treesitter context sticky windows' }},
  })
  -- stylua: ignore end
end

return {
  'nvim-treesitter/nvim-treesitter-context',
  event = 'VeryLazy',
  config = config,
}
