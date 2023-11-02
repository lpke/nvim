-- copy current buffer id and position
Lpke_copied_buffer_info = {}
function Lpke_copy_buffer_id()
  Lpke_copied_buffer_info.id = vim.api.nvim_get_current_buf()
  Lpke_copied_buffer_info.pos = vim.fn.getcurpos()
end

-- paste saved buffer into current window (retain pasteover data)
function Lpke_paste_buffer_id()
  if Lpke_copied_buffer_info.id then
    -- save pasteover buffer info
    local pasteover_buf_id = vim.api.nvim_get_current_buf()
    local pasteover_cursor_pos = vim.fn.getcurpos()

    -- paste saved buffer
    vim.api.nvim_set_current_buf(Lpke_copied_buffer_info.id)
    if Lpke_copied_buffer_info.pos then
      vim.fn.setpos('.', Lpke_copied_buffer_info.pos)
    end

    -- save pasteover buffer info
    Lpke_copied_buffer_info.id = pasteover_buf_id
    Lpke_copied_buffer_info.pos = pasteover_cursor_pos
  end
end

-- window 'zoom' toggling (with per tab support)
Lpke_zoomed = {} -- stores whether tab group/s are in a 'zoomed' state or not
Lpke_zoom_previous = {} -- stores state of previous window layouts
Lpke_zoom_count = {} -- stores number of number of windows at time of last zoom
function Lpke_zoomed_reset_state(equalise)
  Lpke_zoomed = {}
  Lpke_zoom_previous = {}
  Lpke_zoom_count = {}
  if equalise then
    vim.cmd('wincmd =')
  end
end
function Lpke_win_zoom_toggle()
  local ok, err = pcall(function()
    local cur_tab = vim.api.nvim_get_current_tabpage()
    local cur_win = vim.api.nvim_get_current_win()

    if Lpke_zoomed[cur_tab] then
      local wins = vim.api.nvim_tabpage_list_wins(cur_tab)
      if #wins >= Lpke_zoom_count[cur_tab] then
        -- restore the previous layout
        for _, win_info in ipairs(Lpke_zoom_previous[cur_tab]) do
          local win = win_info.win
          vim.api.nvim_set_current_win(win)
          vim.cmd(string.format('resize %d', win_info.height))
          vim.cmd(string.format('vertical resize %d', win_info.width))
        end
        Lpke_zoomed_reset_state()
      else
        print(
          'Un-Zoom: Could not restore previous sizing: Less windows than expected.'
        )
        Lpke_zoomed_reset_state(true)
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
    print('Zoom: Encountered an error: ' .. err)
  end

  -- update lualine
  pcall(function()
    require('lualine').refresh()
  end)
end

-- like print but can print tables
function Lpke_print(val, max_depth, indent_size, indent, current_depth)
  if type(val) ~= 'table' then
    print(val)
  else
    indent_size = indent_size or 2
    indent = indent or ''
    max_depth = max_depth or 0
    current_depth = current_depth or 0

    if current_depth > max_depth then
      print(indent .. '...')
      return
    end

    local next_indent = indent .. string.rep(' ', indent_size)
    for k, v in pairs(val) do
      local key = tostring(k)
      if type(v) == 'table' then
        print(indent .. key .. ':')
        Lpke_print(v, max_depth, indent_size, next_indent, current_depth + 1)
      else
        print(indent .. key .. ': ' .. tostring(v))
      end
    end
  end
end
