-- Shared guards for LPKE CodeCompanion editor-context wrappers.
-- CodeCompanion can keep stale buffer IDs after the source buffer is wiped;
-- these helpers keep #{buffer}/#{diagnostics} from calling Neovim APIs with an
-- invalid bufnr during submit.
local M = {}

function M.valid_bufnr(bufnr)
  return type(bufnr) == 'number'
    and vim.api.nvim_buf_is_valid(bufnr)
    and vim.api.nvim_buf_is_loaded(bufnr)
end

function M.first_valid(...)
  for i = 1, select('#', ...) do
    local bufnr = select(i, ...)
    if M.valid_bufnr(bufnr) then
      return bufnr
    end
  end
  return nil
end

function M.buffer_label(bufnr, fallback)
  if M.valid_bufnr(bufnr) then
    local path = require('codecompanion.utils.buffers').get_info(bufnr).path
    return 'file `' .. path .. '` (with buffer number: ' .. bufnr .. ')'
  end
  return fallback or 'the unavailable source buffer'
end

function M.unavailable(chat, tag, label)
  label = label or tag

  if chat and type(chat.add_message) == 'function' then
    local ok_config, config = pcall(require, 'codecompanion.config')
    if ok_config then
      chat:add_message({
        role = config.constants.USER_ROLE,
        content = label
          .. ' context unavailable: the source buffer was closed or wiped before submit.',
      }, {
        _meta = { source = 'editor_context', tag = tag },
        visible = false,
      })
    end
  end

  if chat then
    chat._lpke_unavailable_context_notified =
      chat._lpke_unavailable_context_notified or {}
    if chat._lpke_unavailable_context_notified[tag] then
      return
    end
    chat._lpke_unavailable_context_notified[tag] = true
  end

  vim.notify(
    label .. ' context skipped: source buffer is unavailable',
    vim.log.levels.WARN,
    { title = 'CodeCompanion' }
  )
end

return M
