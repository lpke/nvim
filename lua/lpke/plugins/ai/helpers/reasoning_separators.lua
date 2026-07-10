-- Codex appends an empty HTML comment to reasoning summaries. Collapse that
-- presentation-only boundary to one line break before writing it to the buffer.
local M = {}

local separator = '\n\n<!-- -->'
local comment = '<!-- -->'
local states = setmetatable({}, { __mode = 'k' })

local function get_state(handler)
  local state = states[handler]
  if not state then
    state = { pending = '', after_separator = false, padding = '' }
    states[handler] = state
  end
  return state
end

local function pending_length(text, target)
  local max_prefix = math.min(#text, #target - 1)
  for length = max_prefix, 1, -1 do
    if text:sub(-length) == target:sub(1, length) then
      return length
    end
  end
  return 0
end

local function pending_start(text, target)
  local held = pending_length(text, target)
  if held == 0 then
    return text:find('%s*$') or (#text + 1)
  end

  local start = #text - held + 1
  while start > 1 and text:sub(start - 1, start - 1):match('%s') do
    start = start - 1
  end
  return start
end

local function indentation(padding)
  return padding:match('[^\r\n]*$') or ''
end

local function filter_chunk(handler, content)
  local state = get_state(handler)
  local text = state.pending .. content
  state.pending = ''
  local output = {}
  local cursor = 1

  while cursor <= #text do
    if state.after_separator then
      local whitespace_end = cursor - 1
      while
        whitespace_end < #text
        and text:sub(whitespace_end + 1, whitespace_end + 1):match('%s')
      do
        whitespace_end = whitespace_end + 1
      end
      if whitespace_end >= cursor then
        state.padding = state.padding .. text:sub(cursor, whitespace_end)
        cursor = whitespace_end + 1
      end

      if cursor > #text then
        break
      end

      local remaining = text:sub(cursor)
      if remaining:sub(1, #comment) == comment then
        state.padding = ''
        cursor = cursor + #comment
      elseif comment:sub(1, #remaining) == remaining then
        state.pending = remaining
        break
      else
        table.insert(output, '\n' .. indentation(state.padding))
        state.after_separator = false
        state.padding = ''
      end
    else
      local start_index, end_index = text:find(separator, cursor, true)
      if start_index then
        local before = text:sub(cursor, start_index - 1):gsub('%s+$', '')
        table.insert(output, before)
        state.after_separator = true
        state.padding = ''
        cursor = end_index + 1
      else
        local remaining = text:sub(cursor)
        local hold_from = pending_start(remaining, separator)
        table.insert(output, remaining:sub(1, hold_from - 1))
        state.pending = remaining:sub(hold_from)
        break
      end
    end
  end

  return table.concat(output)
end

local function finish(handler)
  local state = states[handler]
  states[handler] = nil
  if not state then
    return ''
  end
  if state.after_separator and state.pending ~= '' then
    return '\n' .. indentation(state.padding) .. state.pending
  end
  return state.pending
end

local function patch_transition(handler, method, original_thought)
  local original = handler[method]
  handler[method] = function(self, ...)
    local remaining = finish(self)
    if remaining ~= '' then
      original_thought(self, remaining)
    end
    return original(self, ...)
  end
end

function M.patch()
  local handler = require('codecompanion.interactions.chat.acp.handler')
  if handler._lpke_filter_reasoning_separators then
    return
  end

  local original_thought = handler.handle_thought_chunk
  handler.handle_thought_chunk = function(self, content)
    local filtered = filter_chunk(self, content)
    if filtered ~= '' then
      return original_thought(self, filtered)
    end
  end

  patch_transition(handler, 'handle_message_chunk', original_thought)
  patch_transition(handler, 'process_tool_call', original_thought)
  patch_transition(handler, 'handle_complete', original_thought)
  patch_transition(handler, 'handle_error', original_thought)
  patch_transition(handler, '_clear_permission_queue', original_thought)
  handler._lpke_filter_reasoning_separators = true
end

return M
