-- Native chat, model, ACP session, history and draft APIs with offline transports.
-- nvim --headless -u NONE -l tests/codecompanion_workflows.lua
table.unpack = table.unpack or unpack
local api = vim.api
vim.opt.rtp:prepend(vim.fn.getcwd())
for _, plugin in ipairs({
  'codecompanion.nvim',
  'codecompanion-history.nvim',
  'plenary.nvim',
  'nvim-treesitter',
  'telescope.nvim',
}) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end
require('lpke.core.globals')
vim.o.columns, vim.o.lines = 160, 48
local checks = 0
local function eq(actual, expected, label)
  checks = checks + 1
  assert(
    vim.deep_equal(actual, expected),
    (label or 'Mismatch')
      .. '\n'
      .. vim.inspect(actual)
      .. '\nexpected '
      .. vim.inspect(expected)
  )
end
local function flush()
  vim.wait(30, function()
    return false
  end)
end
local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end
local original_cwd = vim.fn.getcwd()
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/project', 'p')
vim.fn.writefile({ 'fixture project' }, root .. '/project/README.md')
vim.cmd.cd(root .. '/project')
local ai = require('lpke.plugins.ai.helpers.config')
local cc = require('codecompanion')
local adapters = require('codecompanion.adapters')
local guard = require('lpke.plugins.ai.helpers.submit_guard')
cc.setup({
  rules = { opts = { chat = { enabled = false } } },
  adapters = {
    acp = {
      codex = function()
        local adapter = adapters.extend('codex', {
          defaults = {
            session_config_options = {
              model = ai.adapter_default_model('codex'),
              mode = 'Full Access',
              thought_level = 'high',
            },
          },
        })
        adapter.handlers.request.build_messages =
          guard.wrap_acp_build_messages(adapter.handlers.request.build_messages)
        return adapter
      end,
    },
  },
  display = { chat = { auto_scroll = false, show_settings = false } },
  interactions = {
    chat = {
      adapter = 'codex',
      opts = { completion_provider = 'default' },
    },
  },
  extensions = {
    history = {
      enabled = true,
      opts = {
        dir_to_save = root .. '/history',
        expiration_days = 0,
        auto_save = false,
        auto_generate_title = false,
        picker = 'telescope',
      },
    },
  },
})

local Connection = require('codecompanion.acp')
local requests, fail_load = {}, false
local session_options = {
  {
    id = 'model',
    type = 'select',
    category = 'model',
    currentValue = 'gpt-5.6-sol',
    options = {
      { value = 'gpt-6.1-sol', name = 'GPT-6.1 Sol' },
      { value = 'gpt-6-astra', name = 'GPT-6 Astra' },
      { value = 'gpt-5.6-sol', name = 'GPT-5.6 Sol' },
    },
  },
  {
    id = 'mode',
    type = 'select',
    category = 'mode',
    currentValue = 'read',
    options = {
      { value = 'read', name = 'Read Only' },
      { value = 'full', name = 'Full Access' },
    },
  },
  {
    id = 'reasoning_effort',
    type = 'select',
    category = 'thought_level',
    currentValue = 'low',
    options = {
      { value = 'low', name = 'Low' },
      {
        group = 'efforts',
        name = 'Effort',
        options = {
          { value = 'high', name = 'High' },
        },
      },
    },
  },
  {
    id = 'approval_policy',
    type = 'select',
    category = 'approval',
    currentValue = 'never',
    options = {
      { value = 'never', name = 'Never' },
      { value = 'ask', name = 'Ask' },
    },
  },
}
-- Exercise the real lifecycle wrapper around a fake RPC transport, rather than
-- replacing the lifecycle module or bypassing its exact-load/default logic.
Connection.send_rpc_request = function(self, method, params)
  requests[#requests + 1] = { method = method, params = vim.deepcopy(params) }
  if method == self.METHODS.SESSION_LOAD then
    if fail_load then
      self:store_rpc_response({
        id = 0,
        error = { message = 'Fixture session missing' },
      })
      return nil
    end
    if self._on_session_update then
      self._on_session_update({
        sessionUpdate = 'user_message_chunk',
        content = { type = 'text', text = 'Original task' },
      })
      self._on_session_update({
        sessionUpdate = 'agent_message_chunk',
        content = { type = 'text', text = 'Saved response' },
      })
    end
    return { configOptions = vim.deepcopy(session_options) }
  elseif method == self.METHODS.SESSION_SET_CONFIG_OPTION then
    local options = vim.deepcopy(self:get_config_options())
    for _, option in ipairs(options) do
      if option.id == params.configId then
        option.currentValue = params.value
      end
    end
    return { configOptions = options }
  elseif method == self.METHODS.SESSION_LIST then
    return { sessions = {} }
  end
  error('Unexpected RPC method ' .. method)
end
local lifecycle = require('lpke.plugins.ai.helpers.acp_lifecycle')
lifecycle.setup()
local new_connection
new_connection = function(chat, id)
  local conn =
    Connection.new({ adapter = chat.adapter, chat = chat, session_id = id })
  conn.adapter_modified =
    { defaults = vim.deepcopy(chat.adapter.defaults or {}) }
  conn.is_ready = function()
    return true
  end
  conn.is_connected = function(self)
    return self.session_id ~= nil
  end
  conn.can_load_session = function()
    return true
  end
  conn.can_list_sessions = function()
    return true
  end
  conn:_apply_config_options(vim.deepcopy(session_options))
  return conn
end
require('codecompanion.interactions.chat.helpers').create_acp_connection = function(
  chat,
  callback
)
  chat.acp_connection =
    new_connection(chat, chat.acp_session_id or ('fixture-' .. chat.bufnr))
  if callback then
    callback()
  end
end
guard.setup()
local Chat = require('codecompanion.interactions.chat')
local function new_chat(opts)
  local source = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(source, root .. '/source-' .. source .. '.lua')
  api.nvim_set_current_buf(source)
  local chat = assert(Chat.new(vim.tbl_extend('force', {
    adapter = 'codex',
    buffer_context = {
      bufnr = source,
      filetype = 'lua',
      filename = 'fixture.lua',
      lines = {},
    },
  }, opts or {})))
  api.nvim_set_current_buf(chat.bufnr)
  flush()
  return chat
end
local swap = require('lpke.plugins.ai.helpers.model_swap')
local acp_options = require('lpke.plugins.ai.helpers.acp_session_options')
local chat = new_chat()
chat.acp_connection = new_connection(chat, 'original-session')
local conn = chat.acp_connection
eq(swap.get_cur_model(0), 'gpt-5.6-sol', 'ACP current model')
swap.select({ 'sol', 'astra' })
eq(swap.get_cur_model(0), 'gpt-6.1-sol', 'First available cycle model')
swap.select({ 'sol', 'missing-model', 'astra' })
eq(swap.get_cur_model(0), 'gpt-6-astra', 'Skip unavailable cycle model')
swap.select('missing-model')
eq(
  swap.get_cur_model(0),
  'gpt-6-astra',
  'Unavailable exact model retained current model'
)
eq(
  notices[#notices]:find('not available', 1, true) ~= nil,
  true,
  'Unavailable-model warning'
)
eq(
  acp_options.get_current_value('reasoning', 0),
  'Low',
  'Human reasoning label'
)
eq(
  acp_options.get_current_value('approval', 0),
  'Never',
  'Human approval label'
)
eq(swap.get_cur_acp_mode(0), 'Read Only', 'Human mode label')
for _, option in ipairs(conn:get_config_options()) do
  option.name = option.id
end
local original_select, selected_labels = vim.ui.select, nil
vim.ui.select = function(items, opts, callback)
  selected_labels = items
  callback(items[2], 2)
end
acp_options.show_reasoning()
eq(
  acp_options.get_current_value('reasoning', 0),
  'High',
  'Reasoning picker applies selected value'
)
eq(
  selected_labels,
  { '* Low', '  High (Effort)' },
  'Grouped values and current mark rendered'
)
eq(chat.ui:is_visible(), true, 'ACP option picker keeps chat visible')
chat.ui:hide()
eq(
  chat.ui:is_visible(),
  true,
  'Temporary picker visibility guard blocks an incidental hide'
)
acp_options.show_approval()
eq(
  acp_options.get_current_value('approval', 0),
  'Ask',
  'Approval picker applies selected value'
)
vim.ui.select = original_select
chat._lpke_keep_visible_token = nil

-- Apply session defaults on exact loads, in the saved cwd and model-first order.
api.nvim_set_current_buf(chat.bufnr)
chat.cwd, chat.opts.cwd = root .. '/project', root .. '/project'
requests = {}
eq(lifecycle.load_session(chat, 'loaded-session'), true, 'Exact session load')
eq(conn.session_id, 'loaded-session', 'Exact loaded ID')
eq(requests[1].params.cwd, root .. '/project', 'Saved cwd on session/load')
eq(
  requests[2].params.configId,
  'model',
  'Default model applied before other config'
)
eq(swap.get_cur_model(0), 'gpt-6.1-sol', 'Loaded session default model')
eq(swap.get_cur_acp_mode(0), 'Full Access', 'Loaded session default mode')
eq(
  acp_options.get_current_value('reasoning', 0),
  'High',
  'Loaded session reasoning default'
)
fail_load = true
local loaded, load_error = lifecycle.load_session(chat, 'missing-session')
eq(loaded, false, 'Missing session rejected')
eq(load_error, 'Fixture session missing', 'RPC error preserved')
eq(conn.session_id, 'loaded-session', 'Failed load retains previous ID')
eq(conn._loading_session, nil, 'Loading state restored after failure')
eq(
  requests[#requests].method,
  conn.METHODS.SESSION_LOAD,
  'Failure did not create new session'
)
fail_load = false

local history_scope = require('lpke.plugins.ai.helpers.history_scope')
history_scope.setup()
local history_acp = require('lpke.plugins.ai.helpers.history_acp')
history_acp.setup()
local resumed = new_chat()
resumed.acp_connection = new_connection(resumed, 'temporary-session')
eq(
  history_acp.resume_session_into_chat(
    resumed,
    { sessionId = 'resume-exact', title = 'Fixture title' }
  ),
  true,
  'Replay session'
)
eq(resumed.acp_session_id, 'resume-exact', 'Resume remembers exact ID')
eq(
  table
    .concat(api.nvim_buf_get_lines(resumed.bufnr, 0, -1, false), '\n')
    :find('Saved response', 1, true) ~= nil,
  true,
  'Resume renders transcript'
)
eq(resumed.opts.title, 'Fixture title', 'Resume keeps selected title')
eq(
  history_acp.format_session_kind('resume-exact', 'saved'),
  '[xact] [saved]',
  'Short ID marker'
)
local Store = require('codecompanion._extensions.history.storage')
local store =
  Store.new({ dir_to_save = root .. '/history', expiration_days = 0 })
resumed.opts.save_id = 'canonical'
resumed:add_message({ role = 'user', content = 'Original task' })
resumed:add_message({ role = 'llm', content = 'Saved response' })
store:save_chat(resumed)
local second = new_chat()
second.acp_connection = new_connection(second, 'resume-exact')
second.messages = {
  { role = 'user', content = 'Follow up' },
  { role = 'llm', content = 'Additional response' },
}
second.opts.save_id = 'duplicate'
store:save_chat(second)
local saved = store:load_chat(second.opts.save_id)
eq(second.opts.save_id, 'canonical', 'Same session uses canonical save ID')
eq(saved.acp_session_id, 'resume-exact', 'Session ID persisted')
eq(
  #saved.messages >= 4,
  true,
  'Saving partial view retains previous transcript'
)
eq(store:get_chats().duplicate, nil, 'Duplicate entry removed')
eq(
  history_scope.parse_history_prompt('@**  Needle').content_filter,
  'Needle',
  'All-project content syntax'
)
eq(
  history_scope.parse_history_prompt('title  content').search,
  'title',
  'Title/content split'
)
eq(
  history_scope.chat_matches_content(saved, 'follow up'),
  true,
  'Smartcase saved message match'
)
eq(
  history_scope.chat_matches_content(saved, 'FOLLOW UP'),
  false,
  'Uppercase match is case sensitive'
)
eq(
  history_scope.match_col(
    'literal [ pattern',
    history_scope.search_pattern('[')
  ),
  8,
  'Invalid regex falls back to literal search'
)

local drafts = require('lpke.plugins.ai.helpers.drafts')
drafts.setup()
local drafted = new_chat()
drafted.acp_connection = new_connection(drafted, 'draft-session')
drafted.context:add({
  id = 'fixture.lua',
  source = '<buf>',
  opts = { sync_all = true },
})
drafted:add_buf_message({
  role = 'user',
  content = 'Keep this exact draft\n> My own quotation',
})
eq(drafts.save(drafted.bufnr), true, 'Save active prompt')
local items = drafts.list_current_cwd()
eq(#items, 1, 'Exactly one current-cwd draft')
eq(
  items[1].prompt:find('Keep this exact draft\n> My own quotation', 1, true)
    ~= nil,
  true,
  'User quotation preserved'
)
eq(
  items[1].prompt:find('> Context:', 1, true),
  nil,
  'Synthetic context block removed with renamed icons: '
    .. vim.inspect(items[1].prompt)
)
local parser = require('lpke.plugins.ai.helpers.chat_draft')
local exact = [[  Keep these spaces
## Me
## CodeCompanion (Codex)
> Context:
> - user-authored quotation

```markdown
## Me
```
Trailing spaces  ]]
api.nvim_buf_set_lines(drafted.bufnr, drafted.header_line, -1, false, { '' })
drafted.context:render()
drafted:add_buf_message({ role = 'user', content = exact })
eq(
  parser.empty(drafted),
  false,
  'Role headings and blockquotes remain a nonempty draft'
)
eq(drafts.save(drafted.bufnr), true, 'Save Markdown headings and quotation')
items = drafts.list_current_cwd()
eq(#items, 1, 'Editing keeps one draft file')
eq(
  vim.trim(items[1].prompt),
  vim.trim(exact),
  'Stored Markdown structure unchanged'
)
eq(
  items[1].prompt:find('  Keep these spaces', 1, true) ~= nil,
  true,
  'Leading user spaces unchanged'
)
eq(
  items[1].prompt:find('Trailing spaces  ', 1, true) ~= nil,
  true,
  'Trailing user spaces unchanged'
)
local path = items[1].path
api.nvim_exec_autocmds(
  'User',
  { pattern = 'CodeCompanionChatSubmitted', data = { bufnr = drafted.bufnr } }
)
flush()
eq(vim.fn.filereadable(path), 0, 'Submitted draft deleted')
eq(drafts.save(drafted.bufnr), false, 'Submitted text not resurrected')

local registry = require('lpke.plugins.ai.helpers.chat_registry')
eq(registry.get(), drafted, 'Registry current chat')
eq(registry.find_save('canonical'), resumed, 'Canonical saved view found')
eq(
  registry.find_session('resume-exact'),
  resumed,
  'Resumed session found in buffer order'
)
local ordered = registry.list()
for index = 2, #ordered do
  eq(
    ordered[index - 1].bufnr < ordered[index].bufnr,
    true,
    'Registry stable buffer order'
  )
end
local closing = new_chat()
closing.opts.save_id = 'close-me'
closing.acp_connection = new_connection(closing, 'close-me-session')
closing:add_buf_message({
  role = 'user',
  content = 'Keep draft when closing immediately',
})
local bufnr = closing.bufnr
closing:close()
eq(registry.get(bufnr), nil, 'Closed chat no longer registered')
eq(registry.find_save('close-me'), nil, 'No stale saved-chat lookup')
eq(registry.find_session('close-me-session'), nil, 'No stale session lookup')
eq(
  vim.iter(drafts.list_current_cwd()):any(function(item)
    return item.prompt:find('Keep draft when closing immediately', 1, true)
      ~= nil
  end),
  true,
  'Immediate close saves draft before native unregister'
)

vim.cmd.cd(original_cwd)
vim.fn.delete(root, 'rf')
print(
  ('PASS: %d Codex model/session/defaults/resume/history/draft checks'):format(
    checks
  )
)
