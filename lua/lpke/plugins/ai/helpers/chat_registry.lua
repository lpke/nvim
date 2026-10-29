local M = {}

function M.get(bufnr)
  return require('codecompanion').buf_get_chat(bufnr or 0)
end

-- Take a fresh snapshot; opening/closing/resuming chats never needs cache upkeep.
function M.list()
  local chats = {}
  for _, entry in ipairs(require('codecompanion').buf_get_chat()) do
    if entry.chat and vim.api.nvim_buf_is_valid(entry.chat.bufnr) then
      chats[#chats + 1] = entry.chat
    end
  end
  table.sort(chats, function(a, b)
    return a.bufnr < b.bufnr
  end)
  return chats
end

function M.session_id(chat)
  return chat
    and (
      (chat.acp_connection and chat.acp_connection.session_id)
      or chat.acp_session_id
      or (chat.opts and chat.opts.acp_session_id)
    )
end

function M.find_save(save_id)
  if type(save_id) ~= 'string' or save_id == '' then
    return nil
  end
  for _, chat in ipairs(M.list()) do
    if chat.opts and chat.opts.save_id == save_id then
      return chat
    end
  end
end

function M.find_session(session_id)
  if type(session_id) ~= 'string' or session_id == '' then
    return nil
  end
  for _, chat in ipairs(M.list()) do
    if chat.adapter.type == 'acp' and M.session_id(chat) == session_id then
      return chat
    end
  end
end

return M
