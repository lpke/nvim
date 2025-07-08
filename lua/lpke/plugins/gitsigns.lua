local function config()
  local gitsigns = require('gitsigns')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  gitsigns.setup({
    signs = {
      add = { text = '┃' },
      change = { text = '┃' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '┃' },
      untracked = { text = '┆' },
    },
    signs_staged = {
      add = { text = '┃' },
      change = { text = '┃' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '┃' },
      untracked = { text = '┆' },
    },
    signs_staged_enable = true,
    signcolumn = true, -- Toggle with `:Gitsigns toggle_signs`
    numhl = false, -- Toggle with `:Gitsigns toggle_numhl`
    linehl = false, -- Toggle with `:Gitsigns toggle_linehl`
    word_diff = false, -- Toggle with `:Gitsigns toggle_word_diff`
    watch_gitdir = {
      follow_files = true,
    },
    auto_attach = true,
    attach_to_untracked = false,
    current_line_blame = false, -- Toggle with `:Gitsigns toggle_current_line_blame`
    current_line_blame_opts = {
      virt_text = true,
      virt_text_pos = 'right_align', -- 'eol' | 'overlay' | 'right_align'
      delay = 1000,
      ignore_whitespace = false,
      virt_text_priority = 100,
      use_focus = true,
    },
    current_line_blame_formatter = '<author>, <author_time:%R> - <summary>',
    sign_priority = 0,
    update_debounce = 100,
    status_formatter = nil, -- Use default
    max_file_length = 40000, -- Disable if file is longer than this (in lines)
    preview_config = {
      -- Options passed to nvim_open_win
      border = 'rounded',
      relative = 'cursor',
      row = 0,
      col = 1,
    },

    on_attach = function(_bufnr)
      -- stylua: ignore start
      -- TODO: keymap for `:Gitsigns blame`, tidy up
      helpers.keymap_set_multi({
        { 'n', ']C', function()
          if vim.wo.diff then
            vim.cmd.normal({ ']c', bang = true })
          else
            gitsigns.nav_hunk('next', { preview = true })
          end
        end, { desc = 'Gitsigns: Go to the next git hunk (unstaged only)' } },
        { 'n', '[C', function()
          if vim.wo.diff then
            vim.cmd.normal({ '[c', bang = true })
          else
            gitsigns.nav_hunk('prev', { preview = true })
          end
        end, { desc = 'Gitsigns: Go to the previous git hunk (unstaged only)' } },
        { 'n', ']c', function()
          gitsigns.nav_hunk('next', { preview = true, target = 'all' })
        end, { desc = 'Gitsigns: Go to the next git hunk (staged and unstaged)' } },
        { 'n', '[c', function()
          gitsigns.nav_hunk('prev', { preview = true, target = 'all' })
        end, { desc = 'Gitsigns: Go to the previous git hunk (staged and unstaged)' } },

        -- Actions
        -- { 'n', '<leader>hs', gitsigns.stage_hunk, { desc = '' } },
        -- { 'n', '<leader>hr', gitsigns.reset_hunk, { desc = '' } },
        --
        -- { 'v', '<leader>hs', function()
        --   gitsigns.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })
        -- end, { desc = '' } },
        --
        -- { 'v', '<leader>hr', function()
        --   gitsigns.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })
        -- end, { desc = '' } },
        --
        -- { 'n', '<leader>hS', gitsigns.stage_buffer, { desc = '' } },
        -- { 'n', '<leader>hR', gitsigns.reset_buffer, { desc = '' } },

        { 'n', 'gH', gitsigns.preview_hunk, { desc = 'Gitsigns: Preview hunk under cursor in a floating window' } },
        { 'n', 'gD', gitsigns.preview_hunk_inline, { desc = 'Gitsigns: Preview hunk under cursor inline' } },

        { 'n', '<leader>hb', function()
          gitsigns.blame_line({ full = true })
        end, { desc = '' } },

        { 'n', '<leader>hd', gitsigns.diffthis, { desc = '' } },

        { 'n', '<leader>hD', function()
          gitsigns.diffthis('~')
        end, { desc = '' } },

        { 'n', '<leader>hQ', function()
          gitsigns.setqflist('all')
        end, { desc = '' } },
        { 'n', '<leader>hq', gitsigns.setqflist, { desc = '' } },

        -- Toggles
        { 'n', '<leader>Gb', gitsigns.toggle_current_line_blame, { desc = '' } },
        { 'n', '<leader>Gw', gitsigns.toggle_word_diff, { desc = '' } },

        -- TODO: fix this
        -- Text object
        -- { 'ox', 'ih', gitsigns.select_hunk, { desc = '' } },
      })
      -- stylua: ignore end
    end,
  })

  helpers.set_hl_multi({
    ['GitSignsAddInline'] = { bg = tc.addbgbright },
    ['GitSignsChangeInline'] = { bg = tc.changebgbright },
    ['GitSignsDeleteInline'] = { bg = tc.deletebgbright },

    ['GitSignsChangedelete'] = { link = 'GitSignsDelete' },
    ['GitSignsChangedeleteNr'] = { link = 'GitSignsDeleteNr' },
    ['GitSignsChangedeleteCul'] = { link = 'GitSignsDeleteCul' },
    ['GitSignsStagedChangedelete'] = { link = 'GitSignsStagedDelete' },
    ['GitSignsStagedChangedeleteNr'] = { link = 'GitSignsStagedDeleteNr' },
    ['GitSignsStagedChangedeleteCul'] = { link = 'GitSignsStagedDeleteCul' },
  })
end

return {
  'lewis6991/gitsigns.nvim',
  event = 'BufReadPre',
  config = config,
}
