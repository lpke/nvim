Lpke_fugitive_prev_win_id = nil
function Lpke_toggle_git_fugitive(new_tab)
  local windows = vim.api.nvim_tabpage_list_wins(0)
  local fugitive_open = false
  local fugitive_win = nil

  -- get window
  for _, win in ipairs(windows) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')

    if (filetype == 'fugitive') and (bufname:match('^fugitive://')) then
      fugitive_open = true
      fugitive_win = win
      break
    end
  end

  -- toggle
  if fugitive_open then
    vim.api.nvim_win_close(fugitive_win, false)
    if Lpke_fugitive_prev_win_id then
      vim.api.nvim_set_current_win(Lpke_fugitive_prev_win_id)
    end
  else
    Lpke_fugitive_prev_win_id = vim.api.nvim_get_current_win()
    if new_tab then
      vim.cmd('tabnew')
      vim.cmd('Git')
      vim.cmd('only')
    else
      vim.cmd('Git')
    end
  end
end

local function config()
  local helpers = require('lpke.core.helpers')
  -- local tc = Lpke_theme_colors

  -- stylua: ignore start
  helpers.keymap_set_multi({
    {'nv', '<leader>i', function() Lpke_toggle_git_fugitive(true) end, { desc = 'Git: Toggle fugitive window (new tab)' }},
    {'nv', '<leader>I', Lpke_toggle_git_fugitive, { desc = 'Git: Toggle fugitive window' }},
  })
  -- stylua: ignore end
end

return {
  'tpope/vim-fugitive',
  event = 'VeryLazy',
  config = config,
}
