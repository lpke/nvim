local M = {}

local function first_window(layout)
  if layout[1] == 'leaf' then
    return layout[2]
  end
  return first_window(layout[2][1])
end

local function column_windows(layout)
  if layout[1] == 'leaf' then
    return { layout[2] }
  end
  if layout[1] ~= 'col' then
    return nil
  end

  local wins = {}
  for _, child in ipairs(layout[2]) do
    if child[1] ~= 'leaf' then
      return nil
    end
    table.insert(wins, child[2])
  end
  return wins
end

local function move_column(wins, direction)
  local heights = vim.tbl_map(vim.api.nvim_win_get_height, wins)

  vim.api.nvim_set_current_win(wins[1])
  vim.cmd('wincmd ' .. direction)

  for i = 2, #wins do
    vim.fn.win_splitmove(wins[i], wins[i - 1], {
      rightbelow = true,
      vertical = false,
    })
  end

  for i = 1, #wins - 1 do
    vim.api.nvim_win_set_height(wins[i], heights[i])
  end
end

local function smart_rotation(layout, current_win)
  if layout[1] ~= 'row' or #layout[2] ~= 2 then
    return nil
  end

  local left, right = layout[2][1], layout[2][2]
  if left[1] == 'leaf' and left[2] == current_win and right[1] ~= 'leaf' then
    return 'L'
  end
  if right[1] == 'leaf' and right[2] == current_win and left[1] ~= 'leaf' then
    return 'H'
  end
end

function M.rotate_windows()
  local direction =
    smart_rotation(vim.fn.winlayout(), vim.api.nvim_get_current_win())

  vim.cmd('wincmd ' .. (direction or 'r'))
end

function M.flip_sides()
  local layout = vim.fn.winlayout()
  if layout[1] ~= 'row' or #layout[2] ~= 2 then
    vim.notify('Flip sides requires two side-by-side window groups')
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  local left, right = layout[2][1], layout[2][2]
  local left_width = vim.api.nvim_win_get_width(first_window(left))
  local right_wins = column_windows(right)
  local left_wins = column_windows(left)

  if right_wins then
    move_column(right_wins, 'H')
  elseif left_wins then
    move_column(left_wins, 'L')
  else
    vim.notify('Flip sides does not support nested grids yet')
    return
  end

  local flipped_layout = vim.fn.winlayout()
  vim.api.nvim_win_set_width(first_window(flipped_layout[2][1]), left_width)

  if vim.api.nvim_win_is_valid(current_win) then
    vim.api.nvim_set_current_win(current_win)
  end
end

return M
