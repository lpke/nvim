local M = {}
M.__index = M

-- Capture the editor's actual byte spans before leaving Visual mode. Neovim
-- handles reversed, exclusive, linewise and rectangular selections here.
function M.capture()
  local mode = vim.fn.mode()
  local active = mode == 'v' or mode == 'V' or mode == vim.keycode('<C-v>')
  if not active then
    mode = vim.fn.visualmode()
  end
  local first = vim.fn.getpos(active and 'v' or "'<")
  local last = vim.fn.getpos(active and '.' or "'>")
  local regions = vim.fn.getregionpos(first, last, { type = mode, eol = true })
  local parts = {}
  for _, region in ipairs(regions) do
    local start, finish = unpack(region)
    if start[4] ~= 0 or finish[4] ~= 0 then
      return nil, 'Inline selections must start and end on whole characters'
    end
    local line = vim.fn.getline(start[2])
    local end_char = vim.fn.strcharpart(line:sub(finish[3]), 0, 1)
    parts[#parts + 1] = {
      row = start[2],
      first = math.min(math.max(start[3] - 1, 0), #line),
      last = math.min(finish[3] - 1 + #end_char, #line),
    }
  end
  if #parts == 0 then
    return nil, 'No visual selection available for inline editing'
  end
  return setmetatable(
    { parts = parts, mode = mode, block = mode == vim.keycode('<C-v>') },
    M
  )
end

function M:prepare(lines)
  local selected = {}
  for _, part in ipairs(self.parts) do
    local line = lines[part.row] or ''
    part.prefix = line:sub(1, part.first)
    part.suffix = line:sub(part.last + 1)
    selected[#selected + 1] = line:sub(part.first + 1, part.last)
  end
  self.text = table.concat(selected, '\n')
end

-- Reinsert the edited selection while retaining every byte outside its spans.
function M:assemble(edited, original)
  local replacement = vim.split(edited, '\n', { plain = true })
  if self.block then
    if #replacement ~= #self.parts then
      return nil,
        'Block selection edits must preserve the number of selected rows'
    end
    local result = vim.deepcopy(original)
    for index, part in ipairs(self.parts) do
      result[part.row] = part.prefix .. replacement[index] .. part.suffix
    end
    return result
  end

  local first, last = self.parts[1], self.parts[#self.parts]
  replacement[1] = first.prefix .. replacement[1]
  replacement[#replacement] = replacement[#replacement] .. last.suffix
  local result = vim.list_slice(original, 1, first.row - 1)
  vim.list_extend(result, replacement)
  return vim.list_extend(result, vim.list_slice(original, last.row + 1))
end

-- ACP edits a full temporary copy. Its native line guard still runs, then this
-- check rejects any remaining change outside the selected columns.
function M:contains_changes(lines, original)
  local first, last = self.parts[1], self.parts[#self.parts]
  local ending = #lines - (#original - last.row)
  if ending < first.row then
    return false
  end
  if
    not vim.deep_equal(
      vim.list_slice(lines, 1, first.row - 1),
      vim.list_slice(original, 1, first.row - 1)
    )
    or not vim.deep_equal(
      vim.list_slice(lines, ending + 1),
      vim.list_slice(original, last.row + 1)
    )
  then
    return false
  end
  local function retains_edges(line, part)
    return line:sub(1, #part.prefix) == part.prefix
      and (#part.suffix == 0 or line:sub(-#part.suffix) == part.suffix)
      and #line >= #part.prefix + #part.suffix
  end
  if self.block then
    if #lines ~= #original then
      return false
    end
    for _, part in ipairs(self.parts) do
      if not retains_edges(lines[part.row], part) then
        return false
      end
    end
    return true
  end
  return lines[first.row]:sub(1, #first.prefix) == first.prefix
    and (#last.suffix == 0 or lines[ending]:sub(-#last.suffix) == last.suffix)
    and (first.row ~= ending or #lines[ending] >= #first.prefix + #last.suffix)
end

function M:describe()
  local spans = {}
  for _, part in ipairs(self.parts) do
    spans[#spans + 1] = ('line %d, bytes %d-%d'):format(
      part.row,
      part.first + 1,
      part.last
    )
  end
  return 'Only edit the visual selection: '
    .. table.concat(spans, '; ')
    .. '. '
    .. 'The edit_file tool matches old_string only inside the selected text. '
    .. (self.block and 'Keep the same number of selected rows. ' or '')
    .. 'Text outside the selection must remain unchanged.'
end

return M
