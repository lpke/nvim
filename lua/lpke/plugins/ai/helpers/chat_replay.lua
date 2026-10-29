local M = {}
local api = vim.api

-- Session replay replaces the transcript. Keep input composed while the agent
-- was loading, including its context and cursor, outside that replacement.
function M.restore(chat, updates)
  local prompt = require('lpke.plugins.ai.helpers.chat_draft').prompt(chat)
  local lines = prompt
    and api.nvim_buf_get_lines(chat.bufnr, prompt.header, -1, false)
  local items = chat.context_items
  local messages, cursors = {}, {}
  if prompt then
    for _, message in ipairs(chat.messages) do
      if message.context and not (message._meta and message._meta.sent) then
        messages[#messages + 1] = message
      end
    end
    for _, win in ipairs(vim.fn.win_findbuf(chat.bufnr)) do
      local cursor = api.nvim_win_get_cursor(win)
      if cursor[1] > prompt.header then
        cursors[win] = { cursor[1] - prompt.header, cursor[2] }
      end
    end
  end

  require('codecompanion.interactions.chat.acp.render').restore_session(
    chat,
    updates
  )
  if not lines then
    return
  end
  for _, item in ipairs(items) do
    chat.context:add(item)
  end
  for _, message in ipairs(messages) do
    chat:add_message(message, {
      context = message.context,
      _meta = message._meta,
      visible = message.opts and message.opts.visible,
    })
  end
  api.nvim_buf_set_lines(chat.bufnr, chat.header_line, -1, false, lines)
  for win, cursor in pairs(cursors) do
    if
      api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == chat.bufnr
    then
      api.nvim_win_set_cursor(win, { chat.header_line + cursor[1], cursor[2] })
    end
  end
end

return M
