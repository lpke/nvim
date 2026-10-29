local M = {}

function M.open(thread_id)
  local chat_fns = require('lpke.plugins.ai.helpers.chat_functions')
  local chat = chat_fns.open_fullscreen_chat({
    replace_current_window = true,
    silent = true,
    adapter = thread_id and 'codex' or nil,
    acp_session_id = thread_id,
    acp_connection_only = thread_id ~= nil,
    restore_acp_session = thread_id ~= nil,
  })
  pcall(vim.cmd, 'silent! tabonly')
  if require('lpke.core.local_extensions').call('startup_chat', thread_id) then
    return
  end
  if not thread_id then
    return
  end

  if chat then
    chat.opts.acp_connection_only = nil
    require('lpke.plugins.ai.helpers.acp_lifecycle').ensure_chat_connection(
      chat
    )
  end
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
