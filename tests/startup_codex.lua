-- nvim --headless -u NONE -l tests/startup_codex.lua
table.unpack = table.unpack or unpack
vim.opt.rtp:prepend(vim.fn.getcwd())
local opened, resumed, extension_id, error_message
local handled, fail = false, false
local chat = {}
package.loaded['lpke.plugins.ai.helpers.chat_functions'] = {
  open_fullscreen_chat = function(opts)
    opened = opts
  end,
}
package.loaded['lpke.core.local_extensions'] = {
  call = function(name, id)
    assert(name == 'startup_chat')
    extension_id = id
    return handled
  end,
}
package.loaded['codecompanion'] = {
  last_chat = function()
    return chat
  end,
}
package.loaded['lpke.plugins.ai.helpers.acp_lifecycle'] = {
  ensure_chat_ready = function(target, callback)
    assert(target == chat)
    callback()
  end,
}
package.loaded['lpke.plugins.ai.helpers.history_acp'] = {
  resume_session_into_chat = function(target, id)
    assert(target == chat)
    resumed = id
    return not fail, 'Missing session'
  end,
}
vim.notify = function(message)
  error_message = message
end
local startup = require('lpke.plugins.ai.helpers.startup_codex')
local id = '11111111-2222-3333-4444-555555555555'
startup.open()
assert(opened.replace_current_window and not resumed)
startup.open(id)
assert(resumed == id and extension_id == id and opened.adapter == 'codex')
resumed, handled = nil, true
startup.open(id)
assert(not resumed, 'Linked thread bypassed its owner-aware integration')
handled, fail = false, true
startup.open(id)
assert(error_message:find('Missing session', 1, true))
vim.env.LPKE_NVIM_CODEX, vim.env.LPKE_NVIM_CODEX_THREAD = '1', id
startup.open = function(value)
  resumed = value
end
resumed = nil
startup.setup()
assert(vim.env.LPKE_NVIM_CODEX_THREAD == nil)
vim.api.nvim_exec_autocmds('VimEnter', {})
assert(vim.wait(1000, function()
  return resumed == id
end))
print(
  'PASS: blank startup, exact session, linked ownership delegation, failure, and startup flag consumption'
)

-- Exercise the actual CodeCompanion buffer and ACP replay with a fake transport.
-- No agent process or model request is started.
for _, name in ipairs({
  'lpke.plugins.ai.helpers.chat_functions',
  'lpke.core.local_extensions',
  'codecompanion',
  'lpke.plugins.ai.helpers.history_acp',
  'lpke.plugins.ai.helpers.startup_codex',
}) do
  package.loaded[name] = nil
end
for _, plugin in ipairs({
  'codecompanion.nvim',
  'codecompanion-history.nvim',
  'plenary.nvim',
  'nvim-treesitter',
}) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end
require('lpke.core.globals')
require('codecompanion').setup({
  display = { chat = { start_in_insert_mode = false, show_settings = false } },
  interactions = {
    chat = { adapter = 'ollama', opts = { completion_provider = 'default' } },
  },
})
package.loaded['lpke.plugins.ai.helpers.acp_lifecycle'] = {
  ensure_chat_ready = function(target, callback)
    target.acp_connection = {
      is_ready = function()
        return true
      end,
      get_models = function()
        return {}
      end,
      get_config_options = function()
        return {}
      end,
      can_load_session = function()
        return true
      end,
      load_session = function() end,
    }
    callback()
  end,
  load_session = function(target, session_id, opts)
    assert(session_id == id)
    target.acp_connection.session_id = session_id
    opts.on_session_update({
      sessionUpdate = 'user_message_chunk',
      content = { type = 'text', text = 'Saved fixture prompt' },
    })
    opts.on_session_update({
      sessionUpdate = 'agent_message_chunk',
      content = { type = 'text', text = 'Saved fixture response' },
    })
    return true
  end,
  remember_session = function(target)
    target.acp_session_id = target.acp_connection.session_id
  end,
}
require('lpke.plugins.ai.helpers.startup_codex').open(id)
local actual = require('codecompanion').last_chat()
assert(actual.adapter.name == 'codex')
assert(actual.acp_session_id == id)
assert(vim.api.nvim_get_current_buf() == actual.bufnr)
assert(#vim.api.nvim_list_wins() == 1 and #vim.api.nvim_list_tabpages() == 1)
local content =
  table.concat(vim.api.nvim_buf_get_lines(actual.bufnr, 0, -1, false), '\n')
assert(content:find('Saved fixture prompt', 1, true))
assert(content:find('Saved fixture response', 1, true))
print(
  'PASS: actual fullscreen CodeCompanion restores the selected session transcript without sending a prompt'
)
