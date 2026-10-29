-- Exercise the complete production configuration with offline transports.
-- nvim --headless -u NONE -l tests/codecompanion_config.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.loadplugins = true
dofile('init.lua')
local api = vim.api
local checks = 0
local function eq(actual, expected, label)
  checks = checks + 1
  assert(
    vim.deep_equal(actual, expected),
    label
      .. '\n'
      .. vim.inspect(actual)
      .. '\nexpected '
      .. vim.inspect(expected)
  )
end
local function flush()
  vim.wait(40, function()
    return false
  end)
end
local cc = require('codecompanion')
local config = require('codecompanion.config')
local adapters = require('codecompanion.adapters')
local Chat = require('codecompanion.interactions.chat')
local ai = require('lpke.plugins.ai.helpers.config')
local notices, title_prompts = {}, {}
vim.notify = function(message)
  notices[#notices + 1] = message
end
require('lpke.plugins.ai.helpers.title_request').request = function(
  prompt,
  callback
)
  title_prompts[#title_prompts + 1] = prompt
  callback('Configuration fixture')
  return function() end
end
local original_cwd = vim.fn.getcwd()
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
vim.fn.writefile({ 'RULE_CONTEXT_MUST_NOT_APPEAR' }, root .. '/AGENTS.md')
vim.cmd.cd(root)
local disconnections = 0
local function new_connection(chat)
  local model = 'gpt-6.1-sol'
  return {
    session_id = 'config-fixture-' .. root .. '-' .. chat.bufnr,
    is_connected = function()
      return true
    end,
    is_ready = function()
      return true
    end,
    get_models = function()
      return {
        currentModelId = model,
        availableModels = {
          { modelId = 'gpt-6.1-sol', name = 'Sol' },
          { modelId = 'gpt-6-astra', name = 'Astra' },
        },
      }
    end,
    set_model = function(_, value)
      model = value
      return true
    end,
    get_config_options = function()
      return {}
    end,
    build_name_map = function()
      return {}
    end,
    send_notification = function() end,
    disconnect = function()
      disconnections = disconnections + 1
    end,
  }
end
require('codecompanion.interactions.chat.helpers').create_acp_connection = function(
  chat,
  callback
)
  chat.acp_connection = new_connection(chat)
  if callback then
    callback()
  end
end
local chats = {}
local function new_chat(adapter)
  local source = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(source, root .. '/source-' .. source .. '.lua')
  api.nvim_buf_set_lines(source, 0, -1, false, { 'return "fixture"' })
  api.nvim_set_current_buf(source)
  local chat = assert(Chat.new({
    adapter = adapter or 'codex',
    buffer_context = {
      bufnr = source,
      filetype = 'lua',
      filename = 'fixture.lua',
      lines = { 'return "fixture"' },
    },
  }))
  chats[#chats + 1] = chat
  api.nvim_set_current_buf(chat.bufnr)
  flush()
  return chat
end
local chat = new_chat()
eq(config.interactions.chat.adapter, 'codex', 'Default adapter')
eq(ai.adapter_default_model('codex'), 'gpt-6.1-sol', 'Default Codex model')
eq(config.interactions.inline.adapter, 'copilot', 'Inline adapter preserved')
eq(config.interactions.cmd.adapter, 'copilot', 'Command adapter preserved')
eq(
  config.interactions.chat.keymaps.sync_all.callback,
  'keymaps.sync_all',
  'gp active v20 callback'
)
eq(
  config.interactions.chat.keymaps.sync_diff.callback,
  'keymaps.sync_diff',
  'gw active v20 callback'
)
eq(config.interactions.chat.keymaps.clear, nil, 'Clear mapping disabled')
eq(config.display.chat.intro_message, '', 'No intro message')
eq(config.display.chat.fold_reasoning, false, 'Reasoning stays expanded')
eq(config.display.chat.show_header_separator, false, 'No role separator')
local token = require('codecompanion.adapters.http.copilot.token')
local previous_oauth, previous_token = token._oauth_token, token._copilot_token
local previous_path, previous_codespaces =
  vim.env.CODECOMPANION_TOKEN_PATH, vim.env.CODESPACES
token._oauth_token, token._copilot_token = nil, nil
vim.env.CODECOMPANION_TOKEN_PATH, vim.env.CODESPACES = root, nil
eq(token.init(), false, 'Missing OAuth token rejected')
eq(token.init(), false, 'Repeated missing token rejected')
flush()
eq(
  vim
    .iter(notices)
    :filter(function(message)
      return message == 'GitHub Copilot token missing; run :Copilot auth'
    end)
    :totable(),
  { 'GitHub Copilot token missing; run :Copilot auth' },
  'One actionable missing-token notification'
)
eq(
  table
    .concat(vim.fn.readfile(vim.fn.stdpath('state') .. '/codecompanion.log'), '\n')
    :find('Copilot Adapter: No token found', 1, true) ~= nil,
  true,
  'Suppressed notification error remains in log file'
)
token._oauth_token, token._copilot_token = previous_oauth, previous_token
vim.env.CODECOMPANION_TOKEN_PATH, vim.env.CODESPACES =
  previous_path, previous_codespaces
for _, key in ipairs({
  'system_prompt',
  'yolo_mode',
  'clear_approvals',
  'copilot_stats',
}) do
  eq(
    config.interactions.chat.keymaps[key],
    nil,
    'Removed chat control: ' .. key
  )
end
eq(
  config.interactions.chat.keymaps['Generate Summary'],
  nil,
  'HTTP summary generation unavailable'
)
eq(vim.fn.exists(':Adapter'), 2, 'Adapter command retained')
eq(_G.Lpke_cc_adapter, nil, 'No adapter-cycle global')
eq(_G.Lpke_cc_model, nil, 'No model helper global')
eq(
  ai.adapter_default_model('copilot'),
  'claude-sonnet-4.6',
  'Copilot inline/cmd model unchanged'
)
eq(
  config.interactions.chat.roles.llm(chat.adapter),
  'CodeCompanion (Codex)',
  'ACP role wording unchanged'
)

-- Capture the request after real parser/context/system prompt preparation.
local payload
chat._submit_acp = function(_, value)
  payload = value
end
chat:add_buf_message({ role = 'user', content = 'Only this typed task' })
config.interactions.chat.keymaps.send.callback(chat)
flush()
assert(payload, 'Configured Send did not reach ACP transport')
local wire = adapters.call_handler(chat.adapter, 'build_messages', {
  messages = payload.messages,
  capabilities = {},
})
eq(
  wire,
  { { type = 'text', text = 'Only this typed task' } },
  'ACP receives exact typed task without HTTP system/date/context/rules/skills'
)
eq(
  title_prompts,
  { 'Only this typed task' },
  'Title helper receives only typed prompt'
)
chat:add_buf_message({ role = 'llm', content = 'First answer' })
chat.status = 'success'
chat:done({ output = { 'First answer' } })
local first_payload = payload
config.interactions.chat.keymaps.regenerate.callback(chat)
flush()
eq(payload ~= first_payload, true, 'Configured regenerate reaches transport')
eq(notices[#notices], 'Chat regenerated', 'Regenerate notification')
chat:add_buf_message({ role = 'llm', content = 'Regenerated answer' })
chat.status = 'success'
chat:done({ output = { 'Regenerated answer' } })
local cancellations = 0
chat.current_request = {
  cancel = function()
    cancellations = cancellations + 1
  end,
}
config.interactions.chat.keymaps.stop.callback(chat)
flush()
eq(cancellations, 1, 'Configured stop cancels request once')
eq(chat.current_request, nil, 'Stopped request finishes cleanup')
config.interactions.chat.keymaps.stop.callback(chat)
eq(notices[#notices], 'No request to stop', 'Idle stop notice')

eq(
  adapters.resolve('copilot').schema.model.default,
  'claude-sonnet-4.6',
  'Production Copilot adapter model'
)
local codex = adapters.resolve('codex')
eq(codex.commands.default, { 'codex-acp-exec' }, 'Configured ACP launcher')
eq(codex.env.OPENAI_API_KEY, nil, 'No literal OpenAI key placeholder')
eq(codex.env.CODEX_API_KEY, nil, 'No literal Codex key placeholder')
eq(codex.defaults.auth_method, 'chat-gpt', 'ChatGPT login method')
eq(
  vim.json.decode(codex.env.CODEX_CONFIG()).model,
  'gpt-6.1-sol',
  'Codex model environment'
)
eq(
  vim.json.decode(codex.env.CODEX_CONFIG()).model_reasoning_effort,
  'high',
  'Codex reasoning environment'
)
eq(
  adapters.call_handler(
    codex,
    'build_messages',
    { messages = {}, capabilities = {} }
  ),
  { { type = 'text', text = '/status' } },
  'Nested empty ACP payload uses local status'
)
eq(
  adapters.call_handler(codex, 'build_messages', {
    messages = { { role = 'user', content = 'Real task', _meta = {} } },
    capabilities = {},
  }),
  { { type = 'text', text = 'Real task' } },
  'Nested valid ACP payload preserved'
)

-- Switching controls share one API, with native pickers and offline adapters.
config.adapters.http.copilot = function()
  return adapters.extend('ollama', {
    name = 'copilot',
    formatted_name = 'Copilot',
    schema = {
      model = {
        default = 'claude-sonnet-4.6',
        choices = { ['claude-sonnet-4.6'] = {}, ['gpt-5-mini'] = {} },
      },
    },
  })
end
local models = require('lpke.plugins.ai.helpers.model_swap')
local selections, next_adapter, next_model = {}, 'copilot', 'gpt-5-mini'
local original_select = vim.ui.select
vim.ui.select = function(items, opts, callback)
  selections[#selections + 1] = {
    prompt = opts.prompt,
    first = opts.format_item and opts.format_item(items[1]),
  }
  if opts.prompt == 'Select Adapter' then
    callback(next_adapter)
  elseif opts.prompt == 'Select Model' then
    for _, item in ipairs(items) do
      if
        (type(item) == 'table' and (item.id or item.modelId) or item)
        == next_model
      then
        callback(item)
        return
      end
    end
    error('Fixture model absent from native picker')
  else
    error('Unexpected picker ' .. tostring(opts.prompt))
  end
end
local picker_chat = new_chat('copilot')
local ga = config.interactions.chat.keymaps.change_adapter.callback
ga(picker_chat)
flush()
eq(models.get_cur_model(), 'gpt-5-mini', 'ga same-adapter model picker')
eq(selections[1].first, '* copilot', 'Native adapter current marker')
picker_chat.adapter.schema.model.default = function()
  error('Network-backed default invoked while rendering')
end
eq(
  models.get_cur_model(),
  'gpt-5-mini',
  'HTTP model display uses resolved settings'
)
local choice_calls = 0
picker_chat.adapter.schema.model.choices = function()
  choice_calls = choice_calls + 1
  return { ['claude-sonnet-4.6'] = {}, ['gpt-5-mini'] = {} }
end
models.select({ 'missing-model', 'son', 'gpt5m' })
eq(
  models.get_cur_model(),
  'claude-sonnet-4.6',
  'HTTP cycle skips unavailable models'
)
eq(choice_calls, 2, 'One availability lookup plus native model application')
next_adapter, next_model = 'codex', 'gpt-6-astra'
ga(picker_chat)
flush()
eq(picker_chat.adapter.name, 'codex', 'ga changed adapter')
eq(models.get_cur_model(), 'gpt-6-astra', 'ga native ACP model picker')
local connection, current_model =
  picker_chat.acp_connection, models.get_cur_model()
picker_chat:add_message({
  role = 'llm',
  reasoning = { content = 'vendor state' },
  content = 'Answer',
  tools = { calls = {} },
})
picker_chat:add_buf_message({
  role = 'user',
  content = 'Keep exact prompt and tools',
})
local draft_lines = api.nvim_buf_get_lines(picker_chat.bufnr, 0, -1, false)
local messages = vim.deepcopy(picker_chat.messages)
local schemas, in_use =
  picker_chat.tool_registry.schemas, picker_chat.tool_registry.in_use
local disconnects_before = disconnections
next_adapter = 'copilot'
ga(picker_chat)
eq(picker_chat.acp_connection, connection, 'Refused ga keeps live connection')
eq(disconnections, disconnects_before, 'Refused ga never suspends outgoing ACP')
eq(picker_chat.adapter.name, 'codex', 'Refused ga keeps adapter')
eq(models.get_cur_model(), current_model, 'Refused ga keeps model')
eq(
  picker_chat.messages,
  messages,
  'Refused ga preserves vendor-specific history'
)
eq(
  api.nvim_buf_get_lines(picker_chat.bufnr, 0, -1, false),
  draft_lines,
  'Refused ga keeps draft'
)
eq(picker_chat.tool_registry.schemas, schemas, 'Refused ga keeps tool schemas')
eq(picker_chat.tool_registry.in_use, in_use, 'Refused ga keeps active tools')
eq(
  notices[#notices]:find('Start a new chat', 1, true) ~= nil,
  true,
  'Refusal is visible'
)
vim.cmd('Adapter copilot')
eq(
  picker_chat.acp_connection,
  connection,
  ':Adapter shares native refusal guard'
)
vim.cmd('Model sol')
eq(
  models.get_cur_model(),
  'gpt-6.1-sol',
  'Same-adapter model still changes after reasoning'
)
config.display.chat.show_settings = true
local selection_count = #selections
ga(picker_chat)
eq(#selections, selection_count, 'Settings warning prevents picker')
eq(
  notices[#notices]:find("Adapter can't be changed", 1, true) ~= nil,
  true,
  'Settings restriction visible'
)
config.display.chat.show_settings = false
vim.ui.select = original_select

local switched = new_chat()
switched:add_buf_message({
  role = 'user',
  content = 'Adapter-independent draft',
})
local prompt = api.nvim_buf_get_lines(switched.bufnr, 0, -1, false)
vim.cmd('Adapter copilot')
flush()
eq(switched.adapter.name, 'copilot', ':Adapter switches to Copilot')
eq(
  models.get_cur_model(),
  'claude-sonnet-4.6',
  'Switch applies configured Copilot default'
)
eq(
  api.nvim_buf_get_lines(switched.bufnr, 0, -1, false),
  prompt,
  'Switch preserves typed prompt'
)
local leader = vim.g.mapleader or '\\'
local map = vim.fn.maparg(leader .. 'm', 'n', false, true)
assert(type(map.callback) == 'function', 'Model cycle keymap missing')
map.callback()
eq(
  models.get_cur_model(),
  'gpt-5-mini',
  'leader-m cycles current adapter models'
)
map = vim.fn.maparg(leader .. 'M', 'n', false, true)
assert(type(map.callback) == 'function', 'Adapter cycle keymap missing')
map.callback()
flush()
eq(switched.adapter.name, 'codex', 'leader-M switches back to Codex')
eq(
  models.get_cur_model(),
  'gpt-6.1-sol',
  'Switch applies configured Codex default'
)
local callbacks = {}
models.change_adapter(switched, 'copilot', function()
  callbacks[#callbacks + 1] = 'stale-http'
end)
models.change_adapter(switched, 'codex', function()
  callbacks[#callbacks + 1] = 'current-acp'
end)
flush()
eq(
  callbacks,
  { 'current-acp' },
  'Superseded adapter callback cannot mutate current chat'
)
eq(switched.adapter.name, 'codex', 'Rapid switch keeps most recent adapter')

local closing = new_chat()
config.interactions.chat.keymaps.close.callback(closing)
flush()
eq(cc.buf_get_chat(closing.bufnr), nil, 'Configured close removes current chat')
eq(vim.bo.filetype, 'codecompanion', 'Configured close shows another open chat')

for _, target in ipairs(chats) do
  require('lpke.plugins.ai.helpers.drafts').delete_for_buffer(target.bufnr)
  if target.opts.save_id then
    cc.extensions.history.delete_chat(target.opts.save_id)
  end
end
vim.cmd.cd(original_cwd)
vim.fn.delete(root, 'rf')
print(
  ('PASS: %d production Codex config/request and Copilot authentication checks'):format(
    checks
  )
)
