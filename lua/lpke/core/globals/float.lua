-- get accurate screen size (not including tab, status, or cmd bar)
function Lpke_screen()
  local min_row = math.huge
  local min_col = math.huge
  local max_row = 0
  local max_col = 0

  -- loop through all wins in current tab, storing min/max
  local tab_wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win_id in ipairs(tab_wins) do
    local win_w = vim.api.nvim_win_get_width(win_id)
    local win_h = vim.api.nvim_win_get_height(win_id)
    local win_row, win_col = table.unpack(vim.api.nvim_win_get_position(win_id))

    max_row = math.max(max_row, win_row + win_h)
    max_col = math.max(max_col, win_col + win_w)
    min_row = math.min(min_row, win_row)
    min_col = math.min(min_col, win_col)
  end

  local screen_w = max_col - min_col
  local screen_h = max_row - min_row
  return {
    width = screen_w,
    height = screen_h,
    row_start = min_row,
    col_start = min_col,
    row_end = max_row,
    col_end = max_col,
  }
end

-- create a new floating window/scratchpad
function Lpke_new_float(opts)
  -- these values will be kept if absolute numbers
  local width = opts.width
  local height = opts.height

  -- fallbacks if string wrong
  local fb_width = 100
  local fb_height = 20

  -- saving desired values
  local width_expr = opts.width or '0.5w'
  local height_expr = opts.height or '0.5h'
  local min_width = opts.min_width
  local min_height = opts.min_height
  local max_width = opts.max_width
  local max_height = opts.max_height
  local col_offset = opts.col_offset or 0
  local row_offset = opts.row_offset or 0
  local win_opts = opts.win_opts or {}

  -- unsetting custom opts so they dont cause issues later
  opts.width = nil
  opts.height = nil
  opts.min_width = nil
  opts.min_height = nil
  opts.max_width = nil
  opts.max_height = nil
  opts.col_offset = nil
  opts.row_offset = nil
  opts.win_opts = nil

  -- default values (window opts)
  opts.style = opts.style or 'minimal'
  opts.relative = opts.relative or 'editor'
  opts.border = opts.border or 'none'
  local has_border = opts.border ~= 'none'

  -- determine the size of the available screen
  local screen = Lpke_screen()

  -- stylua: ignore start
  local function extract_num(str) return math.abs(string.match(str, '%-?%d+%.?%d*')) end
  local function is_proportional(str) return string.match(str, '^(%d%.?%d?%d?%d?%d?)([wh])$') and true or false end
  local function is_adjust(str) return string.match(str, '^[wh]%-%d+$') and true or false end
  -- stylua: ignore end

  -- handle special width value
  if type(width_expr) == 'string' then
    if is_proportional(width_expr) then
      -- handle 0.5w format
      width = extract_num(width_expr)
      if width > 1 then
        width = 1 -- maximum value of 1 for proportional
      end
      width = math.floor(screen.width * width)
    elseif is_adjust(width_expr) then
      -- handle w-10 format
      width = extract_num(width_expr)
      if width > screen.width then
        width = screen.width - 1 -- cant go to 0 or negative
      end
      width = screen.width - width
    else
      vim.notify(
        'New Float: Invalid width string. Falling back on ' .. fb_width,
        vim.log.levels.WARN
      )
      width = fb_width
    end
  end

  -- handle special height value
  if type(height_expr) == 'string' then
    if is_proportional(height_expr) then
      -- handle 0.5h format
      height = extract_num(height_expr)
      if height > 1 then
        height = 1 -- maximum value of 1 for proportional
      end
      height = math.floor(screen.height * height)
    elseif is_adjust(height_expr) then
      -- handle h-10 format
      height = extract_num(height_expr)
      if height > screen.height then
        height = screen.height - 1 -- cant go to 0 or negative
      end
      height = screen.height - height
    else
      vim.notify(
        'New Float: Invalid height string. Falling back on ' .. fb_height,
        vim.log.levels.WARN
      )
      height = fb_height
    end
  end

  -- handle min w/h
  if min_width then
    width = math.max(width, min_width)
  end
  if min_height then
    height = math.max(height, min_height)
  end
  -- handle max w/h
  if max_width then
    width = math.min(width, max_width)
  end
  if max_height then
    height = math.min(height, max_height)
  end

  -- handle border
  local border_offset = has_border and -1 or 0
  if has_border then
    height = height - 2
    width = width - 2
  end

  -- calculate the position of the floating window
  local row = math.ceil((screen.height - height) / 2)
    + screen.row_start
    + border_offset
    + row_offset
  local col = math.ceil((screen.width - width) / 2)
    + screen.col_start
    + border_offset
    + col_offset

  -- define the floating window's default options and merge user-defined options
  local options = vim.tbl_extend('keep', {
    width = width,
    height = height,
    row = row,
    col = col,
  }, opts)

  local buf = vim.api.nvim_create_buf(false, true) -- create buffer
  local win = vim.api.nvim_open_win(buf, true, options) -- attach buffer to floating window

  for k, v in pairs(win_opts) do
    vim.api.nvim_set_option_value(k, v, { win = win })
  end

  return { buf = buf, win = win }
end

-- create a floating terminal window (used for user command: `Term`)
function Lpke_term(cmd)
  local full = false
  if cmd and string.find(cmd.args, 'full') then
    full = true
  end

  local float = Lpke_new_float({
    width = full and 'w-4' or '0.6w',
    height = full and 'h-2' or '0.6w',
    min_width = full and nil or 100,
    min_height = full and nil or 20,
    title = ' Terminal ',
    title_pos = 'center',
    border = 'rounded',
  })

  vim.cmd('terminal')
  vim.cmd('startinsert')

  local chan_id = vim.b.terminal_job_id
  vim.cmd('sleep 500m')
  vim.api.nvim_chan_send(chan_id, 'cd ' .. vim.fn.getcwd() .. '\n')
  vim.cmd('sleep 100m')
  vim.api.nvim_chan_send(chan_id, 'clear\n')

  return { buf = float.buf, win = float.win, chan_id = chan_id }
end

-- create a floating terminal window running `ranger` (used for user command: `Ranger`)
function Lpke_ranger(cmd)
  local full = false
  if cmd and string.find(cmd.args, 'full') then
    full = true
  end

  local current_dir = vim.fn.expand('%:p:h')

  local float = Lpke_new_float({
    width = full and 'w-4' or '0.6w',
    height = full and 'h-2' or '0.6w',
    min_width = full and nil or 100,
    min_height = full and nil or 20,
    title = ' Ranger ',
    title_pos = 'center',
    border = 'rounded',
  })

  vim.cmd('terminal')
  vim.cmd('startinsert')

  local chan_id = vim.b.terminal_job_id
  vim.cmd('sleep 500m')
  vim.api.nvim_chan_send(chan_id, 'cd ' .. current_dir .. '\n')
  vim.cmd('sleep 100m')
  vim.api.nvim_chan_send(chan_id, 'clear\n')
  vim.cmd('sleep 100m')
  vim.api.nvim_chan_send(chan_id, 'ranger\n')

  return float
end

-- create a floating terminal window running `trash-restore` (used for user command: `TrashRestore`)
function Lpke_trash_restore(dir)
  dir = dir or vim.fn.getcwd()

  local float = Lpke_new_float({
    width = '0.6w',
    height = '0.6w',
    min_width = 100,
    min_height = 20,
    title = ' Trash Restore ',
    title_pos = 'center',
    border = 'rounded',
  })

  vim.cmd('terminal')
  vim.cmd('startinsert')

  local chan_id = vim.b.terminal_job_id
  vim.cmd('sleep 500m')
  vim.api.nvim_chan_send(chan_id, 'cd ' .. dir .. '\n')
  vim.cmd('sleep 100m')
  vim.api.nvim_chan_send(chan_id, 'clear\n')
  vim.cmd('sleep 100m')
  vim.api.nvim_chan_send(chan_id, 'trash-restore\n')

  return float
end
