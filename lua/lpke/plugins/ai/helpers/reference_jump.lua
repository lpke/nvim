local M = {}

local function parse_target(target)
  target = vim.trim(target)
  target = target:gsub('^file://', '')
  target = target:gsub('^[`<({%[]+', ''):gsub('[`>)}%],.;]+$', '')

  local path, line, col = target:match('^(.*):(%d+):(%d+)$')
  if not path then
    path, line = target:match('^(.*):(%d+)$')
  end
  path = path or target

  if vim.startswith(path, '~') then
    path = vim.fn.expand(path)
  elseif not vim.startswith(path, '/') then
    path = vim.fs.normalize(vim.fn.getcwd() .. '/' .. path)
  end

  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  return {
    path = vim.fs.normalize(path),
    line = tonumber(line) or 1,
    col = tonumber(col) or 1,
  }
end

local function add_candidate(candidates, target, start_col, end_col)
  local reference = parse_target(target)
  if reference then
    reference.start_col = start_col
    reference.end_col = end_col
    table.insert(candidates, reference)
  end
end

function M.reference_at(line, col)
  local candidates = {}

  for start_col, target, end_col in line:gmatch('()%[[^%]]-%]%(([^%)]+)%)()') do
    add_candidate(candidates, target, start_col, end_col - 1)
  end
  for start_col, target, end_col in line:gmatch('()`([^`]+)`()') do
    add_candidate(candidates, target, start_col, end_col - 1)
  end
  for start_col, target, end_col in line:gmatch('()([^%s]+)()') do
    add_candidate(candidates, target, start_col, end_col - 1)
  end

  for _, candidate in ipairs(candidates) do
    if col >= candidate.start_col and col <= candidate.end_col then
      candidate.start_col = nil
      candidate.end_col = nil
      return candidate
    end
  end
end

function M.open_under_cursor()
  if require('lpke.core.helpers').open_url_under_cursor() then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local reference =
    M.reference_at(vim.api.nvim_get_current_line(), cursor[2] + 1)
  if not reference then
    vim.notify(
      'CodeCompanion: no URL or readable file reference under cursor',
      vim.log.levels.INFO
    )
    return
  end

  require('codecompanion.utils.ui').tabnew_reuse(reference.path)
  local line_count = vim.api.nvim_buf_line_count(0)
  local line = math.min(reference.line, line_count)
  local line_length = #vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1]
  vim.api.nvim_win_set_cursor(
    0,
    { line, math.min(reference.col - 1, line_length) }
  )
end

return M
