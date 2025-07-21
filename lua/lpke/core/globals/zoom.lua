Lpke_zoomed = {} -- stores whether tab group/s are in a 'zoomed' state or not
Lpke_zoom_previous = {} -- stores state of previous window layouts
Lpke_zoom_count = {} -- stores number of number of windows at time of last zoom

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

-- window 'zoom' toggling (with per tab support)
function Lpke_win_zoom_toggle()
  local ok, err = pcall(function()
    local cur_tab = vim.api.nvim_get_current_tabpage()
    local cur_win = vim.api.nvim_get_current_win()

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
