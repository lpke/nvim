local M = {}

function M.display_content(content)
  if type(content) ~= 'string' or not content:find('data:', 1, true) then
    return content
  end

  -- Codex replays embedded media as text links instead of ACP media blocks.
  -- Keep the attachment label without putting its base64 data in the buffer.
  return content:gsub(
    '(%[@%a+%])%(data:([^;,%)]+);base64,[^%)]*%)',
    function(label, mimetype)
      if
        (label == '[@image]' and mimetype:match('^image/'))
        or (label == '[@audio]' and mimetype:match('^audio/'))
      then
        return label
      end
    end
  )
end

function M.setup()
  local render = require('codecompanion.interactions.chat.acp.render')
  if render._lpke_compact_media then
    return
  end
  render._lpke_compact_media = true

  local original_restore = render.restore_session
  render.restore_session = function(chat, updates)
    local add_message = chat.add_buf_message
    local previous_add_message = rawget(chat, 'add_buf_message')
    chat.add_buf_message = function(self, data, opts)
      if data.role == require('codecompanion.config').constants.USER_ROLE then
        local content = M.display_content(data.content)
        if content ~= data.content then
          data = vim.tbl_extend('force', data, { content = content })
        end
      end
      return add_message(self, data, opts)
    end

    local ok, result = pcall(original_restore, chat, updates)
    chat.add_buf_message = previous_add_message
    if not ok then
      error(result, 0)
    end
    return result
  end
end

return M
