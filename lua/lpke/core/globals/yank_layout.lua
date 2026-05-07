Lpke_copied_buffer_info = {}
function Lpke_copy_buffer()
  Lpke_copied_buffer_info.id = vim.api.nvim_get_current_buf()
  Lpke_copied_buffer_info.pos = vim.fn.getcurpos()
end

-- paste saved buffer into current window (retain pasteover data)
function Lpke_paste_buffer()
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

-- close current window but save info (so it can be quickly restored)
local function notify_close_error(msg)
  vim.schedule(function()
    vim.api.nvim_echo({ { msg, 'ErrorMsg' } }, false, {})
  end)
end

local function close_last_win_to_oil()
  local old_buf = vim.api.nvim_get_current_buf()
  local ok, oil = pcall(require, 'oil')
  if not ok then
    notify_close_error('Cannot close last window: oil.nvim is unavailable')
    return
  end

  local opened, err = pcall(oil.open, vim.fn.getcwd(-1, -1))
  if not opened then
    notify_close_error('Cannot close last window: ' .. tostring(err))
    return
  end

  if
    vim.api.nvim_buf_is_valid(old_buf)
    and old_buf ~= vim.api.nvim_get_current_buf()
  then
    local deleted, delete_err = pcall(vim.api.nvim_buf_delete, old_buf, {
      force = false,
    })
    if not deleted then
      notify_close_error(
        'Cannot close previous buffer: ' .. tostring(delete_err)
      )
    end
  end
end

local function non_float_wins()
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_config(win).relative == ''
  end, vim.api.nvim_list_wins())
end

local function current_tab_non_float_wins()
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_config(win).relative == ''
  end, vim.api.nvim_tabpage_list_wins(0))
end

function Lpke_close_win()
  Lpke_copy_buffer()
  if #non_float_wins() == 1 then
    close_last_win_to_oil()
    return
  end

  local ok, err
  if #current_tab_non_float_wins() == 1 then
    ok, err = pcall(vim.cmd.tabclose)
  else
    ok, err = pcall(vim.api.nvim_win_close, 0, false)
  end
  if not ok then
    notify_close_error(tostring(err))
  end
end

Lpke_copied_layout = {}
Lpke_copied_layout_count = nil
Lpke_copied_layout_tab = nil

function Lpke_layout_reset_state()
  Lpke_copied_layout = {}
  Lpke_copied_layout_count = nil
  Lpke_copied_layout_tab = nil
end

-- copy current tab page layout
function Lpke_copy_layout()
  local ok, err = pcall(function()
    local cur_tab = vim.api.nvim_get_current_tabpage()
    local wins = vim.api.nvim_tabpage_list_wins(cur_tab)
    Lpke_copied_layout = {}
    Lpke_copied_layout_count = #wins
    Lpke_copied_layout_tab = cur_tab
    for _, win in ipairs(wins) do
      local height = vim.api.nvim_win_get_height(win)
      local width = vim.api.nvim_win_get_width(win)
      table.insert(
        Lpke_copied_layout,
        { win = win, height = height, width = width }
      )
    end
  end)
  if not ok then
    Lpke_layout_reset_state()
    vim.notify(
      'Copy layout: Encountered an error: ' .. err,
      vim.log.levels.ERROR
    )
  end
end

-- paste saved tab layout
function Lpke_paste_layout()
  local ok, err = pcall(function()
    -- checking state health and ensure pasting into correct tab
    if #Lpke_copied_layout == 0 then
      Lpke_layout_reset_state()
      vim.notify(
        'Paste layout: Copied layout data is empty. Resetting state and aborting.',
        vim.log.levels.WARN
      )
      return
    end
    if Lpke_copied_layout_count == nil then
      Lpke_layout_reset_state()
      vim.notify(
        'Paste layout: Copied layout count is nil. Resetting state and aborting.',
        vim.log.levels.WARN
      )
      return
    end
    if Lpke_copied_layout_tab == nil then
      Lpke_layout_reset_state()
      vim.notify(
        'Paste layout: Copied layout tab is nil. Resetting state and aborting.',
        vim.log.levels.WARN
      )
      return
    end
    local cur_tab = vim.api.nvim_get_current_tabpage()
    if cur_tab ~= Lpke_copied_layout_tab then
      vim.notify(
        'Paste layout: Current tab does not match copied tab. Aborting.',
        vim.log.levels.WARN
      )
      return
    end

    -- paste layout
    local wins = vim.api.nvim_tabpage_list_wins(cur_tab)
    if #wins >= Lpke_copied_layout_count then
      for _ = 1, 2 do
        for _, win_info in ipairs(Lpke_copied_layout) do
          local win = win_info.win
          vim.api.nvim_win_set_height(win, win_info.height)
          vim.api.nvim_win_set_width(win, win_info.width)
          vim.api.nvim_win_call(win, function()
            vim.cmd('normal! zH') -- scroll left
          end)
        end
      end
    else
      Lpke_layout_reset_state()
      vim.notify(
        'Paste layout: Less windows than expected. Resetting state and aborting.',
        vim.log.levels.WARN
      )
    end
  end)
  if not ok then
    Lpke_layout_reset_state()
    vim.notify(
      'Paste layout: Encountered an error: ' .. err,
      vim.log.levels.ERROR
    )
  end
end
