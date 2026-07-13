---@class lpke.core.helpers.links
local M = {}

local function markdown_url_candidates(line)
  local candidates = {}
  local search_from = 1

  while true do
    local label_start, destination_start = line:find('%b[]%(', search_from)
    if not label_start then
      break
    end

    destination_start = destination_start + 1
    if line:sub(destination_start):match('^https?://') then
      local depth = 1
      local escaped = false

      for index = destination_start, #line do
        local char = line:sub(index, index)
        if escaped then
          escaped = false
        elseif char == '\\' then
          escaped = true
        elseif char == '(' then
          depth = depth + 1
        elseif char == ')' then
          depth = depth - 1
          if depth == 0 then
            table.insert(candidates, {
              url = line:sub(destination_start, index - 1),
              start_col = label_start,
              end_col = index,
            })
            search_from = index + 1
            break
          end
        end
      end

      if depth > 0 then
        break
      end
    else
      search_from = destination_start
    end
  end

  return candidates
end

local function trim_raw_url(url)
  url = url:gsub('[%.,;:!?]+$', '')

  local bracket_pairs = { { '(', ')' }, { '[', ']' }, { '{', '}' } }
  for _, pair in ipairs(bracket_pairs) do
    local _, opens = url:gsub('%' .. pair[1], '')
    local _, closes = url:gsub('%' .. pair[2], '')
    while closes > opens and vim.endswith(url, pair[2]) do
      url = url:sub(1, -2)
      closes = closes - 1
    end
  end

  return url
end

---@param line string
---@param col integer 1-based byte column
---@return string|nil
function M.url_at(line, col)
  for _, candidate in ipairs(markdown_url_candidates(line)) do
    if col >= candidate.start_col and col <= candidate.end_col then
      return candidate.url
    end
  end

  for start_col, raw_url in line:gmatch('()(https?://[^%s<>"`]+)') do
    local url = trim_raw_url(raw_url)
    local end_col = start_col + #url - 1
    if col >= start_col and col <= end_col then
      return url
    end
  end
end

---@param url string
---@return boolean opened
function M.open_url(url)
  local _, err = vim.ui.open(url)
  if err then
    vim.notify('Failed to open URL: ' .. err, vim.log.levels.ERROR)
    return false
  end
  return true
end

---@return boolean opened
function M.open_url_under_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local url = M.url_at(vim.api.nvim_get_current_line(), cursor[2] + 1)
  return url and M.open_url(url) or false
end

return M
