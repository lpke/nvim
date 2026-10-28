---@class lpke.core.helpers.references
local M = {}

local format = require('lpke.core.helpers.format')
local links = require('lpke.core.helpers.links')

local function decode_path(path)
  return (
    path:gsub('%%(%x%x)', function(hex)
      return string.char(tonumber(hex, 16))
    end)
  )
end

local function source_path()
  local name = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype == '' and name ~= '' and not name:find('://', 1, true) then
    return name
  end
end

local function resolve_path(path)
  if path == '' or path:find('%z') then
    return
  end
  path = path:gsub('%${([%w_]+)}', function(name)
    return vim.env[name]
  end)
  path = format.normalize_path(path)

  local source = source_path()
  local cwd = vim.fn.getcwd()
  local bases = { source and vim.fs.dirname(source) or cwd }
  local root = Lpke_find_git_root(source or cwd)
  if root then
    table.insert(bases, root)
  end
  table.insert(bases, cwd)

  local seen = {}
  for _, base in ipairs(bases) do
    local absolute = format.absolute_path(base, path)
    if not seen[absolute] then
      seen[absolute] = true
      if vim.fn.filereadable(absolute) == 1 then
        return absolute
      elseif vim.fn.isdirectory(absolute) == 1 then
        return absolute, true
      end
    end
  end
end

local function parse_target(target)
  target = vim.trim(target)
  if target:match('^file://') then
    local authority, path = target:match('^file://([^/]*)(/.*)$')
    if not path or (authority ~= '' and authority ~= 'localhost') then
      return
    end
    target = path
  elseif target:match('^%a[%w+.-]*://') then
    return
  end

  -- A real filename takes priority over punctuation and location suffixes.
  local path, directory = resolve_path(target)
  if path then
    return { path = path, line = 1, col = 1, directory = directory }
  end

  target = target:gsub('^[`"\'<({%[]+', '')
  target = target:gsub('[`"\'>%]},;.!?]+$', ''):gsub(':+$', '')
  while target:sub(-1) == ')' do
    local _, opens = target:gsub('%(', '')
    local _, closes = target:gsub('%)', '')
    if closes <= opens then
      break
    end
    target = target:sub(1, -2)
  end

  local line, col, anchor
  local filename, fragment = target:match('^(.-)#(.*)$')
  if filename then
    target = filename
    local location = fragment:match('^(L%d+C?%d*)%-L?%d+C?%d*$') or fragment
    line, col = location:match('^L(%d+)C(%d+)$')
    line = line or location:match('^L?(%d+)$')
    anchor = not line and decode_path(fragment) or nil
  else
    filename, line, col = target:match('^(.-):(%d+):(%d+)$')
    if not filename then
      filename, line = target:match('^(.-):(%d+)$')
    end
    target = filename or target
  end

  if target == '' and fragment then
    target = source_path() or ''
  end
  path, directory = resolve_path(target)
  if not path then
    path, directory = resolve_path(decode_path(target))
  end
  if path then
    return {
      path = path,
      line = math.max(tonumber(line) or 1, 1),
      col = math.max(tonumber(col) or 1, 1),
      anchor = anchor,
      directory = directory,
    }
  end
end

---@param line string
---@param col integer 1-based byte column
---@return table|nil
function M.reference_at(line, col)
  local target = links.link_target_at(line, col)
  if target then
    return parse_target(target)
  end

  -- Delimited paths can contain spaces. Prefer them over individual words.
  for _, pair in ipairs({
    { '`', '`' },
    { '"', '"' },
    { "'", "'" },
    { '<', '>' },
  }) do
    local pattern = '()' .. pair[1] .. '(.-)' .. pair[2] .. '()'
    for first, value, last in line:gmatch(pattern) do
      if col >= first and col < last then
        local reference = parse_target(value)
        if reference then
          return reference
        end
      end
    end
  end
  for first, value, last in line:gmatch('()(%S+)()') do
    if col >= first and col < last then
      return parse_target(value)
    end
  end
end

local function heading_line(anchor)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local counts = {}
  for index, text in ipairs(lines) do
    local heading = text:match('^%s*#+%s+(.-)%s*#*%s*$')
    local underline = lines[index + 1] or ''
    if
      not heading
      and (underline:match('^=+%s*$') or underline:match('^%-+%s*$'))
    then
      heading = vim.trim(text)
    end
    if heading then
      local slug =
        heading:lower():gsub('[^%w%s_%-\128-\255]', ''):gsub('%s', '-')
      local count = counts[slug] or 0
      counts[slug] = count + 1
      if (count == 0 and slug or slug .. '-' .. count) == anchor then
        return index
      end
    end
  end
end

---Open a resolved reference, optionally reusing or creating a tab for chat.
---@param reference table
---@param opts? { tab?: boolean }
---@return integer winid
function M.open_file_reference(reference, opts)
  local target_win
  if opts and opts.tab then
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_get_name(buf) == reference.path then
          target_win = win
          break
        end
      end
      if target_win then
        break
      end
    end
  end

  if target_win then
    vim.api.nvim_set_current_win(target_win)
  else
    vim.cmd("normal! m'")
    if vim.api.nvim_buf_get_name(0) ~= reference.path then
      local command = opts and opts.tab and vim.cmd.tabedit or vim.cmd.edit
      command({
        args = { reference.path },
        magic = { file = false, bar = false },
      })
    end
  end

  if not reference.directory then
    local line = reference.anchor and heading_line(reference.anchor)
      or reference.line
    line = math.min(line or 1, vim.api.nvim_buf_line_count(0))
    local text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1]
    vim.api.nvim_win_set_cursor(0, { line, math.min(reference.col - 1, #text) })
    vim.cmd('normal! zv')
  end
  return vim.api.nvim_get_current_win()
end

---@return boolean handled
function M.open_reference_under_cursor()
  if links.open_url_under_cursor() then
    return true
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local reference =
    M.reference_at(vim.api.nvim_get_current_line(), cursor[2] + 1)
  if not reference then
    return false
  end
  M.open_file_reference(reference)
  return true
end

return M
