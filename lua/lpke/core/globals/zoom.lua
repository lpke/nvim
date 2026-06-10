Lpke_zoomed = {} -- stores whether tab group/s are in a 'zoomed' state or not
Lpke_zoom_previous = {} -- stores state of previous window layouts
Lpke_zoom_count = {} -- stores number of number of windows at time of last zoom
Lpke_diffview_rhs_zoomed = {}
Lpke_diffview_rhs_zoom_previous = {}

function Lpke_zoomed_reset_state(equalise, tab_group)
  if not tab_group then
    Lpke_zoomed = {}
    Lpke_zoom_previous = {}
    Lpke_zoom_count = {}
  else
    Lpke_zoomed[tab_group] = false
    Lpke_zoom_previous[tab_group] = nil
    Lpke_zoom_count[tab_group] = nil
  end
  if equalise then
    vim.cmd('wincmd =')
  end
end

function Lpke_diffview_rhs_zoom_reset_state(tab_group)
  if not tab_group then
    Lpke_diffview_rhs_zoomed = {}
    Lpke_diffview_rhs_zoom_previous = {}
  else
    Lpke_diffview_rhs_zoomed[tab_group] = false
    Lpke_diffview_rhs_zoom_previous[tab_group] = nil
  end
end

local function lpke_get_diffview_rhs_zoom_targets()
  local ok, lib = pcall(require, 'diffview.lib')
  if not ok then
    return
  end

  local view = lib.get_current_view()
  if not view or not view.cur_layout or not view.panel then
    return
  end

  local main_win = view.cur_layout:get_main_win()
  local main_winid = main_win and main_win.id
  local panel_winid = view.panel.winid

  if
    not main_winid
    or not panel_winid
    or not vim.api.nvim_win_is_valid(main_winid)
    or not vim.api.nvim_win_is_valid(panel_winid)
  then
    return
  end

  return main_winid, panel_winid
end

function Lpke_diffview_rhs_zoom_toggle()
  local ok, err = pcall(function()
    local cur_tab = vim.api.nvim_get_current_tabpage()
    local cur_win = vim.api.nvim_get_current_win()
    local main_win, panel_win = lpke_get_diffview_rhs_zoom_targets()

    if not main_win or not panel_win then
      Lpke_win_zoom_toggle()
      return
    end

    if Lpke_diffview_rhs_zoomed[cur_tab] then
      local previous = Lpke_diffview_rhs_zoom_previous[cur_tab]

      if previous then
        for _ = 1, 2 do
          for _, win_info in ipairs(previous) do
            if vim.api.nvim_win_is_valid(win_info.win) then
              vim.api.nvim_win_set_height(win_info.win, win_info.height)
              vim.api.nvim_win_set_width(win_info.win, win_info.width)
            end
          end
        end
      else
        vim.cmd('wincmd =')
      end

      Lpke_diffview_rhs_zoom_reset_state(cur_tab)
    else
      local wins = vim.api.nvim_tabpage_list_wins(cur_tab)
      Lpke_diffview_rhs_zoom_previous[cur_tab] = {}

      for _, win in ipairs(wins) do
        table.insert(Lpke_diffview_rhs_zoom_previous[cur_tab], {
          win = win,
          height = vim.api.nvim_win_get_height(win),
          width = vim.api.nvim_win_get_width(win),
        })
      end

      local panel_width = vim.api.nvim_win_get_width(panel_win)
      vim.api.nvim_set_current_win(main_win)
      vim.cmd('wincmd _')

      for _, win in ipairs(wins) do
        if
          vim.api.nvim_win_is_valid(win)
          and win ~= main_win
          and win ~= panel_win
          and vim.api.nvim_win_get_width(win) > 1
        then
          vim.api.nvim_win_set_width(win, 1)
        end
      end

      if vim.api.nvim_win_is_valid(panel_win) then
        vim.api.nvim_win_set_width(panel_win, panel_width)
      end

      local target_width = math.max(1, vim.o.columns - panel_width - 1)
      pcall(vim.api.nvim_win_set_width, main_win, target_width)
      Lpke_diffview_rhs_zoomed[cur_tab] = true
    end

    if vim.api.nvim_win_is_valid(cur_win) then
      vim.api.nvim_set_current_win(cur_win)
    end
  end)

  if not ok then
    Lpke_diffview_rhs_zoom_reset_state()
    vim.notify('Diffview zoom: Encountered an error: ' .. err, vim.log.levels.ERROR)
  end

  pcall(function()
    require('lualine').refresh()
  end)

  Lpke_tabline()
end

-- window 'zoom' toggling (with per tab support)
function Lpke_win_zoom_toggle()
  local ok, err = pcall(function()
    local cur_tab = vim.api.nvim_get_current_tabpage()
    local cur_win = vim.api.nvim_get_current_win()

    if not Lpke_zoomed[cur_tab] and lpke_get_diffview_rhs_zoom_targets() then
      Lpke_diffview_rhs_zoom_toggle()
      return
    end

    if Lpke_zoomed[cur_tab] then
      local wins = vim.api.nvim_tabpage_list_wins(cur_tab)
      if #wins >= Lpke_zoom_count[cur_tab] then
        -- restore the previous layout (loop twice, because it fixes a bug)
        for _ = 1, 2 do
          for _, win_info in ipairs(Lpke_zoom_previous[cur_tab]) do
            local win = win_info.win
            vim.api.nvim_win_set_height(win, win_info.height)
            vim.api.nvim_win_set_width(win, win_info.width)
            vim.api.nvim_win_call(win, function()
              vim.cmd('normal! zH') -- scroll left
            end)
          end
        end
        Lpke_zoomed_reset_state(false, cur_tab)
      else
        vim.notify(
          'Un-Zoom: Could not restore previous sizing: Less windows than expected.',
          vim.log.levels.WARN
        )
        Lpke_zoomed_reset_state(true, cur_tab)
      end
    else
      -- save layout and zoom current window
      local wins = vim.api.nvim_tabpage_list_wins(cur_tab)
      if #wins > 1 then
        Lpke_zoom_previous[cur_tab] = {}
        Lpke_zoom_count[cur_tab] = #wins
        for _, win in ipairs(wins) do
          local height = vim.api.nvim_win_get_height(win)
          local width = vim.api.nvim_win_get_width(win)
          table.insert(
            Lpke_zoom_previous[cur_tab],
            { win = win, height = height, width = width }
          )
        end
        vim.api.nvim_set_current_win(cur_win)
        vim.cmd('wincmd |')
        vim.cmd('wincmd _')
        Lpke_zoomed[cur_tab] = true
      end
    end

    -- restore focus to the original window
    vim.api.nvim_set_current_win(cur_win)
  end)

  -- error occured
  if not ok then
    Lpke_zoomed_reset_state()
    vim.notify('Zoom: Encountered an error: ' .. err, vim.log.levels.ERROR)
  end

  -- update lualine
  pcall(function()
    require('lualine').refresh()
  end)

  -- update tabline
  Lpke_tabline()
end
