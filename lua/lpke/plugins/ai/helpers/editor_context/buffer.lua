-- Safe wrapper around CodeCompanion's #{buffer} editor context.
-- Upstream assumes chat.buffer_context.bufnr is valid; LPKE chat workflows can
-- outlive the source buffer, so validate before delegating and skip cleanly if
-- the buffer disappeared.
local upstream = require('codecompanion.interactions.shared.editor_context.buffer')
local util = require('lpke.plugins.ai.helpers.editor_context.util')

local M = {}
local LOCAL_BUFFER_SOURCE = 'lpke.plugins.ai.helpers.editor_context.buffer'
local UPSTREAM_BUFFER_SOURCE =
  'codecompanion.interactions.shared.editor_context.buffer'

M._find_buffer = upstream._find_buffer

local function use_local_context_source(chat)
  for _, item in ipairs((chat and chat.context_items) or {}) do
    if item.source == UPSTREAM_BUFFER_SOURCE then
      item.source = LOCAL_BUFFER_SOURCE
    end
  end
end

function M.new(args)
  local context = upstream.new(args)
  local chat_render = context.chat_render
  local cli_render = context.cli_render

  function context:chat_render(selected, opts)
    selected = selected or {}

    if self.target then
      local result = chat_render(self, selected, opts)
      use_local_context_source(self.Chat)
      return result
    end

    local bufnr
    if selected.bufnr ~= nil then
      bufnr = util.first_valid(selected.bufnr)
    else
      local chat_context = self.Chat and self.Chat.buffer_context
      bufnr = util.first_valid(
        _G.codecompanion_current_context,
        chat_context and chat_context.bufnr
      )
    end

    if not bufnr then
      util.unavailable(self.Chat, 'buffer', 'Buffer')
      return
    end

    selected = vim.tbl_extend('force', {}, selected, { bufnr = bufnr })
    local result = chat_render(self, selected, opts)
    use_local_context_source(self.Chat)
    return result
  end

  context.output = context.chat_render

  function context:cli_render()
    if
      not self.target
      and not util.first_valid(self.buffer_context and self.buffer_context.bufnr)
    then
      return nil
    end

    return cli_render(self)
  end

  return context
end

function M.replace(prefix, message, bufnr)
  if not message:find(prefix .. '{buffer', 1, true) then
    return message
  end

  local function label_for(target)
    local found = target and upstream._find_buffer(target)
    return util.buffer_label(found or bufnr)
  end

  local result = message
  result = result:gsub(prefix .. '{buffer:([^}]*)}{[^}]*}', function(target)
    return label_for(target)
  end)
  result = result:gsub(prefix .. '{buffer:([^}]*)}', function(target)
    return label_for(target)
  end)

  local replacement = util.buffer_label(bufnr)
  result = result:gsub(prefix .. '{buffer}{[^}]*}', replacement)
  result = result:gsub(prefix .. '{buffer}', replacement)

  return result
end

return M
