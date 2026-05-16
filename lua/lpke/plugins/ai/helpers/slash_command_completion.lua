local M = {}

local trigger = require('codecompanion.triggers').mappings.slash_commands

local function delete_slash_token()
  local bufnr = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ''

  col = math.min(col, #line)

  local before_cursor = line:sub(1, col)
  local token_start = before_cursor:find(vim.pesc(trigger) .. '[%w_-]*$')

  if not token_start then
    return
  end

  local start_col = token_start - 1
  vim.api.nvim_buf_set_text(bufnr, row - 1, start_col, row - 1, col, {})
  vim.api.nvim_win_set_cursor(0, { row, start_col })
end

function M.patch_cmp()
  local ok, source =
    pcall(require, 'codecompanion.providers.completion.cmp.slash_commands')
  if not ok or source._lpke_preserve_line_patch then
    return
  end

  source._lpke_preserve_line_patch = true

  function source:execute(item, callback)
    delete_slash_token()

    local bufnr = item.context and item.context.bufnr
      or vim.api.nvim_get_current_buf()
    local chat = require('codecompanion').buf_get_chat(bufnr)

    require('codecompanion.interactions.chat.slash_commands').run(item, chat)

    callback(item)
    vim.bo[bufnr].buflisted = false
  end
end

return M
