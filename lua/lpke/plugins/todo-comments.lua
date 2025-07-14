local function config()
  local todo_comments = require('todo-comments')
  local helpers = require('lpke.core.helpers')

  local opts = {
    signs = true, -- show icons in the signs column
    sign_priority = 8, -- sign priority
    -- keywords recognized as todo comments
    keywords = {
      FIX = {
        icon = '\u{f024} ', -- icon used for the sign, and in search results
        color = 'error', -- can be a hex color, or a named color (see below)
        alt = { 'FIXME', 'BUG', 'FIXIT', 'ISSUE' }, -- a set of other keywords that all map to this FIX keywords
        -- signs = false, -- configure signs for some keywords individually
      },
      TODO = { icon = '\u{f024} ', color = 'info' },
      HACK = { icon = '\u{f024} ', color = 'warning' },
      WARN = {
        icon = '\u{f024} ',
        color = 'warning',
        alt = { 'WARNING', 'XXX' },
      },
      PERF = {
        icon = '\u{f024} ',
        color = 'warning',
        alt = { 'OPTIM', 'PERFORMANCE', 'OPTIMIZE' },
      },
      NOTE = { icon = '\u{f024} ', color = 'hint', alt = { 'INFO' } },
      TEST = {
        icon = '\u{f024} ',
        color = 'default',
        alt = { 'TESTING', 'PASSED', 'FAILED' },
      },
    },
    gui_style = {
      fg = 'NONE', -- The gui style to use for the fg highlight group.
      bg = 'BOLD', -- The gui style to use for the bg highlight group.
    },
    merge_keywords = false, -- when true, custom keywords will be merged with the defaults
    -- highlighting of the line containing the todo comment
    -- * before: highlights before the keyword (typically comment characters)
    -- * keyword: highlights of the keyword
    -- * after: highlights after the keyword (todo text)
    highlight = {
      multiline = false, -- enable multine todo comments
      multiline_pattern = '^.', -- lua pattern to match the next multiline from the start of the matched keyword
      multiline_context = 10, -- extra lines that will be re-evaluated when changing a line
      before = '', -- "fg" or "bg" or empty
      keyword = 'wide', -- "fg", "bg", "wide", "wide_bg", "wide_fg" or empty. (wide and wide_bg is the same as bg, but will also highlight surrounding characters, wide_fg acts accordingly but with fg)
      after = 'fg', -- "fg" or "bg" or empty
      pattern = [[.*<(KEYWORDS)\s*:]], -- pattern or table of patterns, used for highlighting (vim regex)
      comments_only = true, -- uses treesitter to match keywords in comments only
      max_line_len = 400, -- ignore lines longer than this
      exclude = {}, -- list of file types to exclude highlighting
    },
    -- list of named colors where we try to extract the guifg from the
    -- list of highlight groups or use the hex color if hl not found as a fallback
    colors = {
      error = { 'DiagnosticError', 'ErrorMsg', '#eb6f92' },
      warning = { 'DiagnosticWarn', 'WarningMsg', '#f6c177' },
      info = { 'DiagnosticInfo', '#9ccfd8' },
      hint = { 'DiagnosticHint', '#c4a7e7' },
      default = { 'Identifier', '#c4a7e7' },
    },
    search = {
      command = 'rg',
      args = {
        '--color=never',
        '--no-heading',
        '--with-filename',
        '--line-number',
        '--column',
      },
      -- regex that will be used to match keywords.
      -- don't replace the (KEYWORDS) placeholder
      pattern = [[\b(KEYWORDS):]], -- ripgrep regex
      -- pattern = [[\b(KEYWORDS)\b]], -- match without the extra colon. You'll likely get false positives
    },
  }
  todo_comments.setup(opts)

  local telescope_filtered = false
  local function switch_todo_telescope()
    if telescope_filtered then
      vim.cmd('TodoTelescope')
    else
      vim.cmd(
        'TodoTelescope keywords=TODO,FIX,'
          .. table.concat(opts.keywords.FIX.alt, ',')
      )
    end
    telescope_filtered = not telescope_filtered
  end

  -- stylua: ignore start
  helpers.keymap_set_multi({
    {'n', ']t', function()
      todo_comments.jump_next()
    end, { square_repeat = true, desc = 'TodoComments: Next comment' }},
    {'n', '[t', function()
      todo_comments.jump_prev()
    end, { square_repeat = true, desc = 'TodoComments: Previous comment' }},
    {'nC', '<BS>,', 'TodoTelescope', { desc = 'TodoComments: Open Telescope picker for todo comments' }},
  })
  -- telescope-only keymaps
  helpers.telescope_keymap_set_multi('Find Todo', {
    { 'ni', '<F2>s', switch_todo_telescope, { desc = 'TodoComments: Toggle Telescope picker to display TODO and FIX only' }},
    { 'ni', '<A-s>', switch_todo_telescope, { desc = 'TodoComments: Toggle Telescope picker to display TODO and FIX only' }},
  })
  -- stylua: ignore end
end

return {
  'folke/todo-comments.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = config,
}
