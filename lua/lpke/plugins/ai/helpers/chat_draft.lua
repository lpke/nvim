local M = {}
local api = vim.api

function M.read(chat)
  return table.concat(
    api.nvim_buf_get_lines(chat.bufnr, chat.header_line, -1, false),
    '\n'
  )
end

function M.has_prompt(chat)
  local ok, message = pcall(
    require('codecompanion.interactions.chat.parser').messages,
    chat,
    chat.header_line
  )
  return ok
    and message ~= nil
    and type(message.content) == 'string'
    and vim.trim(message.content) ~= ''
end

function M.empty(chat)
  local lines = api.nvim_buf_get_lines(chat.bufnr, chat.header_line, -1, false)
  local context = { '> Context:' }
  local icons = require('codecompanion.config').display.chat.icons
  for _, item in pairs(chat.context_items or {}) do
    if item and not (item.opts and item.opts.visible == false) then
      local icon = item.opts and item.opts.sync_all and icons.buffer_sync_all
        or item.opts and item.opts.sync_diff and icons.buffer_sync_diff
        or ''
      context[#context + 1] = '> - ' .. icon .. item.id
    end
  end
  -- Context:render inserts these exact rows after the first blank draft row.
  -- Never discard arbitrary blockquotes: they may be the user's draft.
  if #context > 1 then
    for i, line in ipairs(context) do
      if lines[i + 1] ~= line then
        return false
      end
    end
    for _ = 1, #context do
      table.remove(lines, 2)
    end
  end
  return vim.trim(table.concat(lines, '\n')) == ''
end

return M
