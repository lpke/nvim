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
      helpers.keymap_set_multi({
        -- navigate between hunks
        { 'n', ']C', function()
          if vim.wo.diff then
            vim.cmd.normal({ ']c', bang = true })
          else
            gitsigns.nav_hunk('next', { preview = true })
          end
        end, { square_repeat = true, desc = 'Gitsigns: Go to the next git hunk (unstaged only)' } },
        { 'n', '[C', function()
          if vim.wo.diff then
            vim.cmd.normal({ '[c', bang = true })
          else
            gitsigns.nav_hunk('prev', { preview = true })
          end
        end, { square_repeat = true, desc = 'Gitsigns: Go to the previous git hunk (unstaged only)' } },
        { 'n', ']c', function()
          gitsigns.nav_hunk('next', { preview = true, target = 'all' })
        end, { square_repeat = true, desc = 'Gitsigns: Go to the next git hunk (staged and unstaged)' } },
        { 'n', '[c', function()
          gitsigns.nav_hunk('prev', { preview = true, target = 'all' })
        end, { square_repeat = true, desc = 'Gitsigns: Go to the previous git hunk (staged and unstaged)' } },

        -- stage/unstage/reset hunks
        { 'n', 'gss', gitsigns.stage_hunk, { desc = 'Gitsigns: Stage or unstage the hunk under the cursor' } },
        { 'v', 'gss', function()
          gitsigns.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })
        end, { desc = 'Gitsigns: Stage or unstage the hunk/s in the visual selection' } },
        { 'n', 'gsX', gitsigns.reset_hunk, { desc = 'Gitsigns: Reset the hunk under the cursor' } },
        { 'v', 'gsX', function()
          gitsigns.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })
        end, { desc = 'Gitsigns: Reset the hunk/s in the visual selection' } },

        -- stage/unstage/reset buffer
        { 'n', '<leader>gss', gitsigns.stage_buffer, { desc = 'Gitsigns: Stage all hunks in the current buffer' } },
        { 'n', '<leader>gsS', gitsigns.reset_buffer_index, { desc = 'Gitsigns: Unstage all hunks in the current buffer' } },
        { 'n', '<leader>gsX', gitsigns.reset_buffer, { desc = 'Gitsigns: Reset all hunks in the current buffer' } },

        -- preview hunks
        { 'n', 'gsh', gitsigns.preview_hunk, { desc = 'Gitsigns: Preview hunk under cursor in a floating window' } },
        { 'n', 'gsl', gitsigns.preview_hunk_inline, { desc = 'Gitsigns: Preview hunk under cursor inline' } },

        -- open buffer blame
        { 'n', 'gsb', gitsigns.blame, { desc = 'Gitsigns: Open blame for current buffer' } },

        -- add hunks to quickfix list
        { 'n', 'gsq', function()
          gitsigns.setqflist(0, { open = false })
          vim.cmd('botright copen')
        end, { desc = 'Gitsigns: Set quickfix list to location of unstaged git hunks (current file)' } },
        { 'n', '<leader>gsq', function()
          gitsigns.setqflist('attached', { open = false })
          vim.cmd('botright copen')
        end, { desc = 'Gitsigns: Set quickfix list to location of unstaged git hunks (open buffers)' } },
        { 'n', 'gsQ', function()
          gitsigns.setqflist('all', { open = false })
          vim.cmd('botright copen')
        end, { desc = 'Gitsigns: Set quickfix list to location of unstaged git hunks (all files, all associated git repos)' } },

        -- toggles
        { 'n', '<F2>z', gitsigns.toggle_signs, { desc = 'Gitsigns: Toggle git changes in sign column' } },
        { 'n', '<A-z>', gitsigns.toggle_signs, { desc = 'Gitsigns: Toggle git changes in sign column' } },

        -- Text object
        { 'ox', 'ih', gitsigns.select_hunk, { desc = '' } },
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
