---@class lpke.core.helpers.links
local M = {}

local function closing_paren(line, start_col)
  local depth, escaped = 1, false
  local quote, angle
  for index = start_col + 1, #line do
    local char = line:sub(index, index)
    if escaped then
      escaped = false
    elseif char == '\\' then
      escaped = true
    elseif quote then
      if char == quote then
        quote = nil
      end
    elseif angle then
      angle = char ~= '>'
    elseif char == '<' then
      angle = true
    elseif
      (char == '"' or char == "'")
      and line:sub(index - 1, index - 1):match('%s')
    then
      quote = char
    elseif char == '(' then
      depth = depth + 1
    elseif char == ')' then
      depth = depth - 1
      if depth == 0 then
        return index
      end
    end
  end
end

local function destination(text)
  text = vim.trim(text)
  local target
  if text:sub(1, 1) == '<' then
    target = text:match('^<(.-)>')
  else
    -- Whitespace starts an optional title, except inside nested parentheses.
    local depth, escaped = 0, false
    local last = #text
    for index = 1, #text do
      local char = text:sub(index, index)
      if escaped then
        escaped = false
      elseif char == '\\' then
        escaped = true
      elseif char == '(' then
        depth = depth + 1
      elseif char == ')' then
        depth = depth - 1
      elseif char:match('%s') and depth == 0 then
        last = index - 1
        break
      end
    end
    target = text:sub(1, last)
  end
  if target and target ~= '' then
    return (target:gsub('\\([%p%s])', '%1'))
  end
end

local function reference_id(label)
  return vim.trim(label):gsub('%s+', ' '):lower()
end

local function reference_destination(label, bufnr)
  local id = reference_id(label)
  local lines = vim.api.nvim_buf_get_lines(bufnr or 0, 0, -1, false)
  for index, line in ipairs(lines) do
    local key, text = line:match('^%s*%[([^%]]+)%]:%s*(.*)$')
    if key and reference_id(key) == id then
      return destination(text ~= '' and text or lines[index + 1] or '')
    end
  end
end

---Find a Markdown destination from either its label or its path/URL.
---@param line string
---@param col integer 1-based byte column
---@param bufnr? integer
---@return string|nil
function M.link_target_at(line, col, bufnr)
  local search_from = 1
  while true do
    local first, last = line:find('%b[]', search_from)
    if not first then
      return
    end

    local label = line:sub(first + 1, last - 1)
    local next_char = line:sub(last + 1, last + 1)
    local target
    if next_char == '(' then
      local finish = closing_paren(line, last + 1)
      if finish then
        target = destination(line:sub(last + 2, finish - 1))
        last = finish
      end
    elseif next_char == '[' then
      local ref_first, ref_last = line:find('%b[]', last + 1)
      if ref_first == last + 1 then
        local id = line:sub(ref_first + 1, ref_last - 1)
        if col >= first and col <= ref_last then
          target = reference_destination(id ~= '' and id or label, bufnr)
        end
        last = ref_last
      end
    elseif next_char == ':' then
      target = destination(line:sub(last + 2))
      last = #line
    elseif col >= first and col <= last then
      target = reference_destination(label, bufnr)
    end

    if col >= first and col <= last then
      return target
    end
    search_from = last + 1
  end
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
  local target = M.link_target_at(line, col)
  if target then
    return target:match('^https?://') and target or nil
  end

  for start_col, raw_url in line:gmatch('()(https?://[^%s<>"\'`]+)') do
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

---@param path string
---@return boolean opened
function M.open_directory(path)
  path = vim.fs.normalize(path)
  if vim.fn.isdirectory(path) ~= 1 then
    vim.notify('Directory does not exist: ' .. path, vim.log.levels.ERROR)
    return false
  end

  local _, err = vim.ui.open(path)
  if err then
    vim.notify('Failed to open directory: ' .. err, vim.log.levels.ERROR)
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
