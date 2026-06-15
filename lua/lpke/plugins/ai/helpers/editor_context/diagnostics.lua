-- Safe wrapper around CodeCompanion's #{diagnostics} editor context.
-- The diagnostics renderer calls buffer APIs through codecompanion.utils.buffers;
-- if the original source buffer has been wiped, submit should warn and continue
-- instead of raising "Invalid buffer id".
local upstream =
  require('codecompanion.interactions.shared.editor_context.diagnostics')
local util = require('lpke.plugins.ai.helpers.editor_context.util')

local M = {}

function M.new(args)
  local context = upstream.new(args)
  local chat_render = context.chat_render
  local cli_render = context.cli_render

  function context:_resolve_bufnr()
    if self.target then
      local found =
        require('codecompanion.interactions.shared.editor_context.buffer')._find_buffer(
          self.target
        )
      return util.first_valid(found)
    end

    local buffer_context = self.buffer_context
      or (self.Chat and self.Chat.buffer_context)
    return util.first_valid(buffer_context and buffer_context.bufnr)
  end

  function context:chat_render()
    if not self:_resolve_bufnr() then
      util.unavailable(self.Chat, 'diagnostics', 'Diagnostics')
      return
    end

    return chat_render(self)
  end

  function context:cli_render()
    if not self:_resolve_bufnr() then
      return nil
    end

    return cli_render(self)
  end

  return context
end

return M
