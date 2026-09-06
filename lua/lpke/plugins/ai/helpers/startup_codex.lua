local M = {}

function M.open(thread_id)
  local chat_fns = require('lpke.plugins.ai.helpers.chat_functions')
  chat_fns.open_fullscreen_chat({
    replace_current_window = true,
    silent = true,
    adapter = thread_id and 'codex' or nil,
  })
  pcall(vim.cmd, 'silent! tabonly')
  if require('lpke.core.local_extensions').call('startup_chat', thread_id) then
    return
  end
  if not thread_id then
    return
  end

  local chat = require('codecompanion').last_chat()
  local lifecycle = require('lpke.plugins.ai.helpers.acp_lifecycle')
  lifecycle.ensure_chat_ready(chat, function()
    local ok, err =
      require('lpke.plugins.ai.helpers.history_acp').resume_session_into_chat(
        chat,
        thread_id
      )
    if not ok then
      vim.notify(
        'Could not open Codex thread: ' .. tostring(err),
        vim.log.levels.ERROR
      )
    end
  end)
end

function M.setup()
  if vim.env.LPKE_NVIM_CODEX ~= '1' then
    return
  end
  local thread_id = vim.env.LPKE_NVIM_CODEX_THREAD
  vim.env.LPKE_NVIM_CODEX_THREAD = nil
  if thread_id == '' then
    thread_id = nil
  end
  local function open()
    M.open(thread_id)
  end
  if vim.v.vim_did_enter == 1 then
    vim.schedule(open)
  else
    vim.api.nvim_create_autocmd('VimEnter', {
      once = true,
      group = vim.api.nvim_create_augroup(
        'LpkeCodeCompanionStartupCodex',
        { clear = true }
      ),
      callback = function()
        vim.schedule(open)
      end,
    })
  end
end

return M
