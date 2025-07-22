Lpke_fugitive_prev_win_id = nil
function Lpke_toggle_git_fugitive(new_tab)
  local fugitive_open = false
  local fugitive_win = nil
  local fugitive_tab = nil

  -- get and set fugitive state
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local windows = vim.api.nvim_tabpage_list_wins(tab)
    for _, win in ipairs(windows) do
      local bufnr = vim.api.nvim_win_get_buf(win)
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      local filetype =
        vim.api.nvim_get_option_value('filetype', { buf = bufnr })

      if (filetype == 'fugitive') and (bufname:match('^fugitive://')) then
        fugitive_open = true
        fugitive_win = win
        fugitive_tab = tab
        break
      end
    end
    if fugitive_open then
      break
    end
  end

  -- toggle
  if
    fugitive_open
    and type(fugitive_win) == 'number'
    and type(fugitive_tab) == 'number'
  then
    local cur_win = vim.api.nvim_get_current_win()
    local cur_tab = vim.api.nvim_get_current_tabpage()

    -- close if active
    if fugitive_tab == cur_tab and fugitive_win == cur_win then
      vim.api.nvim_win_close(fugitive_win, false)
      if Lpke_fugitive_prev_win_id then
        vim.api.nvim_set_current_win(Lpke_fugitive_prev_win_id)
      end
    else
      -- focus if not active
      vim.api.nvim_set_current_tabpage(fugitive_tab)
      vim.api.nvim_set_current_win(fugitive_win)
    end
  else
    if Lpke_find_git_root(vim.fn.getcwd()) ~= nil then
      Lpke_fugitive_prev_win_id = vim.api.nvim_get_current_win()
      if new_tab then
        vim.cmd('tabnew')
        vim.cmd('Git')
        vim.cmd('only')
      else
        vim.cmd('Git')
      end
    else
      vim.notify(
        'Toggle Fugitive: Not in a git repository.',
        vim.log.levels.ERROR
      )
      Lpke_fugitive_prev_win_id = nil
      fugitive_open = false
      fugitive_win = nil
      fugitive_tab = nil
      return
    end
  end
end

-- will be diffed against HEAD unless `against_staging` is true
Lpke_fugitive_diff_original_win_id = nil
Lpke_fugitive_diff_before_win_id = nil
Lpke_fugitive_diff_after_win_id = nil
Lpke_fugitive_diff_autocmd_id = nil
function Lpke_toggle_git_diff(opts)
  opts = opts or {}
  opts.new_tab = opts.new_tab == nil and true or opts.new_tab
  opts.against_staging = opts.against_staging == nil and false
    or opts.against_staging

  -- TODO: handle new_tab option

  -- handle if a diff is already open
  if
    Lpke_fugitive_diff_original_win_id
    or Lpke_fugitive_diff_before_win_id
    or Lpke_fugitive_diff_after_win_id
  then
    -- invalid state: warn and reset
    if
      type(Lpke_fugitive_diff_original_win_id) ~= 'number'
      or type(Lpke_fugitive_diff_before_win_id) ~= 'number'
      or type(Lpke_fugitive_diff_after_win_id) ~= 'number'
    then
      vim.notify(
        'Lpke_toggle_git_diff: Invalid fugitive diff window IDs detected. Resetting state.',
        vim.log.levels.WARN
      )
      if Lpke_fugitive_diff_autocmd_id then
        vim.api.nvim_del_autocmd(Lpke_fugitive_diff_autocmd_id)
      end
      if
        Lpke_fugitive_diff_before_win_id
        and vim.api.nvim_win_is_valid(Lpke_fugitive_diff_before_win_id)
      then
        vim.api.nvim_win_close(Lpke_fugitive_diff_before_win_id, false)
      end
      if
        Lpke_fugitive_diff_after_win_id
        and vim.api.nvim_win_is_valid(Lpke_fugitive_diff_after_win_id)
      then
        vim.api.nvim_win_close(Lpke_fugitive_diff_after_win_id, false)
      end
      Lpke_fugitive_diff_original_win_id = nil
      Lpke_fugitive_diff_before_win_id = nil
      Lpke_fugitive_diff_after_win_id = nil
      Lpke_fugitive_diff_autocmd_id = nil
      return
    else
      local current_win_id = vim.api.nvim_get_current_win()
      -- in original window: focus back to already-open tab
      if current_win_id == Lpke_fugitive_diff_original_win_id then
        vim.api.nvim_set_current_win(Lpke_fugitive_diff_after_win_id)
        return
      -- in a diff window already: close windows
      elseif
        current_win_id == Lpke_fugitive_diff_before_win_id
        or current_win_id == Lpke_fugitive_diff_after_win_id
      then
        if
          Lpke_fugitive_diff_before_win_id
          and vim.api.nvim_win_is_valid(Lpke_fugitive_diff_before_win_id)
        then
          vim.api.nvim_win_close(Lpke_fugitive_diff_before_win_id, false)
        end
        if
          Lpke_fugitive_diff_after_win_id
          and vim.api.nvim_win_is_valid(Lpke_fugitive_diff_after_win_id)
        then
          vim.api.nvim_win_close(Lpke_fugitive_diff_after_win_id, false)
        end
        vim.api.nvim_set_current_win(Lpke_fugitive_diff_original_win_id)
        return
      else
        -- in a new window: close old diffs and proceed afresh
        Lpke_fugitive_diff_original_win_id = current_win_id
        if Lpke_fugitive_diff_autocmd_id then
          vim.api.nvim_del_autocmd(Lpke_fugitive_diff_autocmd_id)
          Lpke_fugitive_diff_autocmd_id = nil
        end
        if vim.api.nvim_win_is_valid(Lpke_fugitive_diff_before_win_id) then
          vim.api.nvim_win_close(Lpke_fugitive_diff_before_win_id, false)
        end
        Lpke_fugitive_diff_before_win_id = nil
        if vim.api.nvim_win_is_valid(Lpke_fugitive_diff_after_win_id) then
          vim.api.nvim_win_close(Lpke_fugitive_diff_after_win_id, false)
        end
        Lpke_fugitive_diff_after_win_id = nil
      end
    end
  end

  Lpke_fugitive_diff_original_win_id = vim.api.nvim_get_current_win()
  vim.cmd('tab split')
  Lpke_fugitive_diff_after_win_id = vim.api.nvim_get_current_win()
  if opts.against_staging then
    vim.cmd('Gvdiffsplit')
  else
    vim.cmd('Gvdiffsplit HEAD')
  end
  Lpke_fugitive_diff_before_win_id = vim.api.nvim_get_current_win()
  if not opts.against_staging then
    vim.cmd('wincmd R')
  end
  vim.api.nvim_set_current_win(Lpke_fugitive_diff_after_win_id)
  vim.cmd('normal! zz')
  vim.cmd('normal! <C-e>')
  vim.cmd('normal! <C-y>')

  local close_in_progress = false
  local function close_win_and_focus_original(win_id)
    if close_in_progress then
      return
    end
    close_in_progress = true
    vim.schedule(function()
      if win_id and vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_win_close(win_id, false)
      end
      if
        Lpke_fugitive_diff_original_win_id
        and vim.api.nvim_win_is_valid(Lpke_fugitive_diff_original_win_id)
      then
        vim.api.nvim_set_current_win(Lpke_fugitive_diff_original_win_id)
      end
      Lpke_fugitive_diff_original_win_id = nil
      Lpke_fugitive_diff_before_win_id = nil
      Lpke_fugitive_diff_after_win_id = nil
      Lpke_fugitive_diff_autocmd_id = nil
      close_in_progress = false
    end)
  end

  -- ensure both new windows close together and origianl is focused again
  Lpke_fugitive_diff_autocmd_id = vim.api.nvim_create_autocmd('WinClosed', {
    pattern = {
      tostring(Lpke_fugitive_diff_before_win_id),
      tostring(Lpke_fugitive_diff_after_win_id),
    },
    callback = function(args)
      local closed_win_id = tonumber(args.match)
      if closed_win_id == Lpke_fugitive_diff_before_win_id then
        close_win_and_focus_original(Lpke_fugitive_diff_after_win_id)
      elseif closed_win_id == Lpke_fugitive_diff_after_win_id then
        close_win_and_focus_original(Lpke_fugitive_diff_before_win_id)
      end
    end,
    once = true,
  })
end

local function config()
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- stylua: ignore start
  helpers.keymap_set_multi({
    {'nv', '<leader>i', function() Lpke_toggle_git_fugitive(true) end, { desc = 'Fugitive: Toggle fugitive window (`:Git` in new tab)' }},
    {'nC', '<leader>gb', 'Git blame', { desc = 'Fugitive: Open blame panel' }},
    {'nv', '<leader>gdd', function() Lpke_toggle_git_diff({ new_tab = true }) end, { desc = 'Fugitive: Open diff split for current file (against HEAD) in a new tab' }},
    {'nv', '<leader>gds', function() Lpke_toggle_git_diff({ new_tab = true, against_staging = true }) end, { desc = 'Fugitive: Open diff split for current file (against staging) in a new tab' }},
    {'nv', 'gsL', function() Lpke_toggle_git_diff({ new_tab = false }) end, { desc = 'Fugitive: Open diff split for current file (against HEAD)' }},
  })
  -- stylua: ignore end

  helpers.set_hl_multi({
    ['FugitiveblameTime'] = { fg = tc.subtle },
    ['FugitiveblameDelimiter'] = { fg = tc.base },
  })
end

return {
  'tpope/vim-fugitive',
  event = 'VeryLazy',
  config = config,
}
