local M = { buffers = {} }
local api = vim.api
local requests = require('lpke.plugins.ai.helpers.request_state')
local namespace = api.nvim_create_namespace('LpkeCodeCompanionSpinner')
local symbols =
  { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

local function clear(bufnr)
  M.buffers[bufnr] = nil
  if api.nvim_buf_is_valid(bufnr) then
    api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  end
  if next(M.buffers) == nil and M.timer then
    M.timer:stop()
    M.timer:close()
    M.timer = nil
  end
end

function M:update_spinner()
  for bufnr, state in pairs(self.buffers) do
    if
      not api.nvim_buf_is_valid(bufnr)
      or vim.bo[bufnr].filetype ~= 'codecompanion'
    then
      requests.clear(bufnr)
    else
      state.index = state.index % #symbols + 1
      api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
      api.nvim_buf_set_extmark(
        bufnr,
        namespace,
        api.nvim_buf_line_count(bufnr) - 1,
        0,
        {
          virt_lines = {
            { { symbols[state.index] .. ' Processing...', 'Comment' } },
          },
        }
      )
    end
  end
end

function M:init()
  requests.subscribe('chat_spinner', function(bufnr, busy)
    if not busy then
      clear(bufnr)
      return
    end
    self.buffers[bufnr] = self.buffers[bufnr] or { index = 0 }
    if not self.timer then
      self.timer = vim.uv.new_timer()
      self.timer:start(
        0,
        100,
        vim.schedule_wrap(function()
          self:update_spinner()
        end)
      )
    end
  end)
end

return M
