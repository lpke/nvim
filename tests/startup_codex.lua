-- Startup routing contract; real transport is in codecompanion_startup_transport.lua.
vim.opt.rtp:prepend(vim.fn.getcwd())
local opened, connected, extension_id
local handled = false
local chat
package.loaded['lpke.plugins.ai.helpers.chat_functions'] = {
  open_fullscreen_chat = function(opts)
    opened = opts
    chat = { opts = vim.deepcopy(opts) }
    return chat
  end,
}
package.loaded['lpke.core.local_extensions'] = {
  call = function(name, id)
    assert(name == 'startup_chat')
    extension_id = id
    if id then
      assert(
        chat.opts.acp_connection_only,
        'owner hook ran after automatic session establishment'
      )
    end
    return handled
  end,
}
package.loaded['lpke.plugins.ai.helpers.acp_lifecycle'] = {
  ensure_chat_connection = function(target)
    assert(target == chat)
    assert(not target.opts.acp_connection_only)
    connected = target.opts.acp_session_id
  end,
}
local startup = require('lpke.plugins.ai.helpers.startup_codex')
local id = '11111111-2222-3333-4444-555555555555'
startup.open()
assert(opened.replace_current_window and not connected)
startup.open(id)
assert(connected == id and extension_id == id and opened.adapter == 'codex')
assert(opened.acp_session_id == id and opened.restore_acp_session)
connected, handled = nil, true
startup.open(id)
assert(
  not connected and chat.opts.acp_connection_only,
  'delegated thread bypassed owner integration'
)
vim.env.LPKE_NVIM_CODEX, vim.env.LPKE_NVIM_CODEX_THREAD = '1', id
startup.open = function(value)
  connected = value
end
startup.setup()
assert(vim.env.LPKE_NVIM_CODEX_THREAD == nil)
vim.api.nvim_exec_autocmds('VimEnter', {})
assert(vim.wait(1000, function()
  return connected == id
end))
print(
  'PASS: blank startup, early exact-session flags, delegated ownership and startup flag consumption'
)
