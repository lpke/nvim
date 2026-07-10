local M = {}

local function remove_heading(lines, heading, blank_side)
  local heading_index
  for index = 1, math.min(#lines, 3) do
    if lines[index] == heading then
      heading_index = index
      break
    end
  end

  if not heading_index then
    return 0
  end

  local removed = 0
  if blank_side == 'after' and lines[heading_index + 1] == '' then
    table.remove(lines, heading_index + 1)
    removed = removed + 1
  elseif
    blank_side == 'before'
    and heading_index > 2
    and lines[heading_index - 1] == ''
    and lines[heading_index - 2] == ''
  then
    table.remove(lines, heading_index - 1)
    heading_index = heading_index - 1
    removed = removed + 1
  end

  table.remove(lines, heading_index)
  return removed + 1
end

local function normalize_leading_blanks(lines, target)
  local count = 0
  while lines[count + 1] == '' do
    count = count + 1
  end

  local line_delta = 0
  while count > target do
    table.remove(lines, 1)
    count = count - 1
    line_delta = line_delta - 1
  end
  while count < target do
    table.insert(lines, 1, '')
    count = count + 1
    line_delta = line_delta + 1
  end
  return line_delta
end

local function adjust_offsets(opts, fold_info, line_delta)
  if line_delta == 0 then
    return
  end

  if opts._icon_info and opts._icon_info.line_offset then
    opts._icon_info.line_offset =
      math.max(0, opts._icon_info.line_offset + line_delta)
  end

  if fold_info then
    fold_info.start_offset = math.max(0, fold_info.start_offset + line_delta)
    fold_info.end_offset = math.max(0, fold_info.end_offset + line_delta)
  end
end

local function patch_formatter(module, heading, blank_side, should_remove)
  local formatter = require(module)
  if formatter._lpke_hide_reasoning_headings then
    return
  end

  local original_format = formatter.format
  formatter.format = function(self, message, opts, state)
    local remove = should_remove(state)
    local lines, fold_info = original_format(self, message, opts, state)
    local line_delta = 0
    if remove then
      line_delta = line_delta - remove_heading(lines, heading, blank_side)
    end
    if state.is_new_response then
      local leading_blanks = 0
      if message.role == 'user' and message.content == '' then
        leading_blanks = 1
      end
      line_delta = line_delta + normalize_leading_blanks(lines, leading_blanks)
    elseif state.is_new_block and state.block_index > 0 then
      line_delta = line_delta + normalize_leading_blanks(lines, 2)
    end
    adjust_offsets(opts, fold_info, line_delta)
    return lines, fold_info
  end
  formatter._lpke_hide_reasoning_headings = true
end

function M.patch()
  patch_formatter(
    'codecompanion.interactions.chat.ui.formatters.reasoning',
    '### Reasoning',
    'after',
    function(state)
      return not state.has_reasoning_output
    end
  )
  patch_formatter(
    'codecompanion.interactions.chat.ui.formatters.standard',
    '### Response',
    'before',
    function(state)
      return state.has_reasoning_output
    end
  )
  patch_formatter(
    'codecompanion.interactions.chat.ui.formatters.tools',
    '### Response',
    'before',
    function(state)
      return state.has_reasoning_output
    end
  )
end

return M
