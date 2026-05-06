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

Lpke_fdiff_orig_win = nil
Lpke_fdiff_before_win = nil
Lpke_fdiff_after_win = nil
Lpke_fdiff_autocmd_id = nil
---Fugitive `Gvdiffsplit` wrapper that allows extra options and adds QoL functionality.
function Lpke_toggle_git_diff(opts)
  opts = opts or {}
  opts.against_staging = opts.against_staging == nil and false
    or opts.against_staging

  -- handle if a diff is already open
  if Lpke_fdiff_orig_win or Lpke_fdiff_before_win or Lpke_fdiff_after_win then
    -- invalid state: warn and reset
    if
      type(Lpke_fdiff_orig_win) ~= 'number'
      or type(Lpke_fdiff_before_win) ~= 'number'
      or type(Lpke_fdiff_after_win) ~= 'number'
    then
      vim.notify(
        'Lpke_toggle_git_diff: Invalid fugitive diff window IDs detected. Resetting state.',
        vim.log.levels.WARN
      )
      if Lpke_fdiff_autocmd_id then
        vim.api.nvim_del_autocmd(Lpke_fdiff_autocmd_id)
      end
      if
        Lpke_fdiff_before_win
        and vim.api.nvim_win_is_valid(Lpke_fdiff_before_win)
      then
        vim.api.nvim_win_close(Lpke_fdiff_before_win, false)
      end
      if
        Lpke_fdiff_after_win
        and vim.api.nvim_win_is_valid(Lpke_fdiff_after_win)
      then
        vim.api.nvim_win_close(Lpke_fdiff_after_win, false)
      end
      Lpke_fdiff_orig_win = nil
      Lpke_fdiff_before_win = nil
      Lpke_fdiff_after_win = nil
      Lpke_fdiff_autocmd_id = nil
      return
    else
      local current_win_id = vim.api.nvim_get_current_win()
      -- in original window: focus back to already-open tab
      if current_win_id == Lpke_fdiff_orig_win then
        vim.api.nvim_set_current_win(Lpke_fdiff_after_win)
        return
      -- in a diff window already: close windows
      elseif
        current_win_id == Lpke_fdiff_before_win
        or current_win_id == Lpke_fdiff_after_win
      then
        if
          Lpke_fdiff_before_win
          and vim.api.nvim_win_is_valid(Lpke_fdiff_before_win)
        then
          vim.api.nvim_win_close(Lpke_fdiff_before_win, false)
        end
        if
          Lpke_fdiff_after_win
          and vim.api.nvim_win_is_valid(Lpke_fdiff_after_win)
        then
          vim.api.nvim_win_close(Lpke_fdiff_after_win, false)
        end
        vim.api.nvim_set_current_win(Lpke_fdiff_orig_win)
        return
      else
        -- in a new window: close old diffs and proceed afresh
        Lpke_fdiff_orig_win = current_win_id
        if Lpke_fdiff_autocmd_id then
          vim.api.nvim_del_autocmd(Lpke_fdiff_autocmd_id)
          Lpke_fdiff_autocmd_id = nil
        end
        if vim.api.nvim_win_is_valid(Lpke_fdiff_before_win) then
          vim.api.nvim_win_close(Lpke_fdiff_before_win, false)
        end
        Lpke_fdiff_before_win = nil
        if vim.api.nvim_win_is_valid(Lpke_fdiff_after_win) then
          vim.api.nvim_win_close(Lpke_fdiff_after_win, false)
        end
        Lpke_fdiff_after_win = nil
      end
    end
  end

  Lpke_fdiff_orig_win = vim.api.nvim_get_current_win()
  vim.cmd('tab split')
  Lpke_fdiff_after_win = vim.api.nvim_get_current_win()
  if opts.against_staging then
    vim.cmd('Gvdiffsplit')
  else
    vim.cmd('Gvdiffsplit HEAD')
  end
  Lpke_fdiff_before_win = vim.api.nvim_get_current_win()
  if not opts.against_staging then
    vim.cmd('wincmd R')
  end
  vim.api.nvim_set_current_win(Lpke_fdiff_after_win)
  vim.cmd('normal! zz')
  vim.cmd('normal! <C-e>')
  vim.cmd('normal! <C-y>')

  -- stylua: ignore start
  -- apply window-specific highlight swaps (equivilent to diffview's `enhanced_diff_hl`)
  vim.api.nvim_win_call(Lpke_fdiff_before_win, function()
    local ns = vim.api.nvim_create_namespace('lpke_fugitive_before_' .. Lpke_fdiff_before_win)
    vim.api.nvim_win_set_hl_ns(Lpke_fdiff_before_win, ns)
    vim.api.nvim_set_hl(ns, 'DiffAdd', vim.api.nvim_get_hl(0, { name = 'DiffviewDiffAddAsDelete' })) ---@diagnostic disable-line: param-type-mismatch
    vim.api.nvim_set_hl(ns, 'DiffDelete', vim.api.nvim_get_hl(0, { name = 'DiffviewDiffDeleteDim' })) ---@diagnostic disable-line: param-type-mismatch
    vim.api.nvim_set_hl(ns, 'DiffChange', vim.api.nvim_get_hl(0, { name = 'DiffviewDiffChange' })) ---@diagnostic disable-line: param-type-mismatch
    vim.api.nvim_set_hl(ns, 'DiffText', vim.api.nvim_get_hl(0, { name = 'DiffviewDiffText' })) ---@diagnostic disable-line: param-type-mismatch
  end)
  vim.api.nvim_win_call(Lpke_fdiff_after_win, function()
    local ns = vim.api.nvim_create_namespace('lpke_fugitive_after_' .. Lpke_fdiff_after_win)
    vim.api.nvim_win_set_hl_ns(Lpke_fdiff_after_win, ns)
    vim.api.nvim_set_hl(ns, 'DiffDelete', vim.api.nvim_get_hl(0, { name = 'DiffviewDiffDeleteDim' })) ---@diagnostic disable-line: param-type-mismatch
    vim.api.nvim_set_hl(ns, 'DiffAdd', vim.api.nvim_get_hl(0, { name = 'DiffviewDiffAdd' })) ---@diagnostic disable-line: param-type-mismatch
    vim.api.nvim_set_hl(ns, 'DiffChange', vim.api.nvim_get_hl(0, { name = 'DiffviewDiffChange' })) ---@diagnostic disable-line: param-type-mismatch
    vim.api.nvim_set_hl(ns, 'DiffText', vim.api.nvim_get_hl(0, { name = 'DiffviewDiffText' })) ---@diagnostic disable-line: param-type-mismatch
  end)
  -- stylua: ignore end

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
        Lpke_fdiff_orig_win
        and vim.api.nvim_win_is_valid(Lpke_fdiff_orig_win)
      then
        vim.api.nvim_set_current_win(Lpke_fdiff_orig_win)
      end
      Lpke_fdiff_orig_win = nil
      Lpke_fdiff_before_win = nil
      Lpke_fdiff_after_win = nil
      Lpke_fdiff_autocmd_id = nil
      close_in_progress = false
    end)
  end

  -- ensure both new windows close together and origianl is focused again
  Lpke_fdiff_autocmd_id = vim.api.nvim_create_autocmd('WinClosed', {
    pattern = {
      tostring(Lpke_fdiff_before_win),
      tostring(Lpke_fdiff_after_win),
    },
    callback = function(args)
      local closed_win_id = tonumber(args.match)
      if closed_win_id == Lpke_fdiff_before_win then
        close_win_and_focus_original(Lpke_fdiff_after_win)
      elseif closed_win_id == Lpke_fdiff_after_win then
        close_win_and_focus_original(Lpke_fdiff_before_win)
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
    {'nv', '<leader>I', function() Lpke_toggle_git_fugitive(true) end, { desc = 'Fugitive: Toggle fugitive window (`:Git` in new tab)' }},
    {'nC', '<leader>gb', 'Git blame', { desc = 'Fugitive: Open blame panel' }},
    {'nv', '<leader>gdd', function() Lpke_toggle_git_diff() end, { desc = 'Fugitive: Open diff split for current file (against HEAD) in a new tab' }},
    {'nv', 'gsL', function() Lpke_toggle_git_diff() end, { desc = 'Fugitive: Open diff split for current file (against HEAD) in a new tab' }},
    {'nv', '<leader>gds', function() Lpke_toggle_git_diff({ against_staging = true }) end, { desc = 'Fugitive: Open diff split for current file (against staging) in a new tab' }},
  })

  helpers.ft_keymap_set_multi('fugitive', {
    {'nv', '<leader>i', function() Lpke_toggle_git_fugitive(true) end, { desc = 'Fugitive: Close fugitive window' }},
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
