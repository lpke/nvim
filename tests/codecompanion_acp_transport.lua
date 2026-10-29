-- Run with the complete config: nvim --headless -i NONE -c "lua dofile('tests/codecompanion_acp_transport.lua')"
local api = vim.api
local config = require('codecompanion.config')
local Chat = require('codecompanion.interactions.chat')
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, 'p')
fixture = assert(vim.uv.fs_realpath(fixture))
local factory = config.adapters.acp.codex
local profile = 'normal'
local original_title = require('lpke.plugins.ai.helpers.title_request').request
local chats, checks, events = {}, 0, {}
local function check(value, label)
  checks = checks + 1
  assert(value, label)
end
local function records()
  local rows = {}
  for _, line in ipairs(vim.fn.readfile(fixture .. '/wire.jsonl')) do
    rows[#rows + 1] = vim.json.decode(line)
  end
  return rows
end
local function by_method(rows, method)
  return vim.tbl_filter(function(row)
    return row.method == method
  end, rows)
end
config.adapters.acp.codex = function()
  local adapter = factory()
  adapter.commands.default = {
    'python3',
    vim.fn.getcwd() .. '/tests/helpers/fake_acp.py',
    fixture .. '/wire.jsonl',
    profile,
  }
  return adapter
end
require('lpke.plugins.ai.helpers.title_request').request = function(_, callback)
  vim.schedule(function()
    callback('Fixture title')
  end)
  return function() end
end
local group =
  api.nvim_create_augroup('LpkeACPTransportFixture', { clear = true })
api.nvim_create_autocmd('User', {
  group = group,
  pattern = { 'CodeCompanionRequestStarted', 'CodeCompanionRequestFinished' },
  callback = function(args)
    events[#events + 1] = { event = args.match, data = args.data }
  end,
})
local function run()
  local lifecycle = require('lpke.plugins.ai.helpers.acp_lifecycle')
  local chat = assert(Chat.new({ adapter = 'codex' }))
  chats[#chats + 1] = chat
  check(
    vim.wait(6000, function()
      return chat.acp_connection and chat.acp_connection:is_connected()
    end, 10),
    'ACP process initializes and authenticates'
  )
  check(
    vim.wait(6000, function()
      return #by_method(records(), 'session/set_config_option') >= 3
    end, 10),
    'default configuration finishes'
  )
  local rows = records()
  check(#by_method(rows, 'initialize') == 1, 'one initialize')
  check(
    by_method(rows, 'authenticate')[1].params.methodId == 'chat-gpt',
    'configured auth method'
  )
  check(#by_method(rows, 'session/new') == 1, 'one session/new')
  check(
    by_method(rows, 'session/new')[1].params.cwd == vim.fn.getcwd(),
    'session cwd'
  )
  local defaults = by_method(rows, 'session/set_config_option')
  check(
    #defaults == 3 and defaults[1].params.configId == 'model',
    'all configured defaults, model first'
  )
  check(
    chat.acp_connection:get_models().currentModelId == 'gpt-6.1-sol',
    'configured model'
  )
  local function full_access(connection)
    for _, option in ipairs(connection:get_config_options()) do
      if option.category == 'mode' then
        return option.currentValue == 'full-access'
      end
    end
    return false
  end
  check(
    vim.wait(6000, function()
      return full_access(chat.acp_connection)
    end, 10),
    'new session uses advertised full-access alias'
  )
  local spawn = rows[1]
  local settings = vim.json.decode(spawn.config)
  check(
    settings.model == 'gpt-6.1-sol'
      and settings.model_reasoning_effort == 'high',
    'launcher configuration reaches actual child'
  )
  check(
    vim.wait(6000, function()
      return not lifecycle.is_preparing(chat)
    end, 10),
    'initial defaults fully ready'
  )
  local prompt = 'Read `/tmp/fixture.png` exactly.'
  api.nvim_buf_set_lines(chat.bufnr, -1, -1, false, { prompt })
  chat:submit()
  check(
    vim.wait(6000, function()
      return #events >= 2 and not chat.current_request
    end, 10),
    'real ACP submission streams and finishes'
  )
  rows = records()
  local prompts = by_method(rows, 'session/prompt')
  check(#prompts == 1, 'one prompt on wire')
  check(
    vim.deep_equal(
      prompts[1].params.prompt,
      { { type = 'text', text = prompt } }
    ),
    'image path remains exact plain text, no rules/base64/context duplication'
  )
  local content =
    table.concat(api.nvim_buf_get_lines(chat.bufnr, 0, -1, false), '\n')
  check(content:find('Fixture reasoning', 1, true), 'thought chunk rendered')
  check(content:find('Fixture reply', 1, true), 'answer chunk rendered')
  check(
    not content:find('### Reasoning', 1, true)
      and not content:find('### Response', 1, true),
    'synthetic headings suppressed'
  )
  local ns = api.nvim_get_namespaces()['lpke-codecompanion-reasoning']
  check(
    #api.nvim_buf_get_extmarks(chat.bufnr, ns, 0, -1, {}) > 0,
    'streamed reasoning highlighted'
  )
  local spinner = require('lpke.plugins.ai.helpers.chat_spinner')
  check(
    not require('lpke.plugins.ai.helpers.request_state').busy(chat)
      and spinner.timer == nil,
    'wire completion stops spinner'
  )
  check(
    events[1].data.bufnr == chat.bufnr and events[2].data.bufnr == chat.bufnr,
    'events route to actual chat'
  )
  check(chat.title == 'Fixture title', 'title callback updates same live chat')
  local resumed =
    assert(Chat.new({ adapter = 'codex', acp_session_id = 'saved-fixture-id' }))
  chats[#chats + 1] = resumed
  check(
    vim.wait(6000, function()
      return resumed.acp_connection and resumed.acp_connection:is_connected()
    end, 10),
    'saved session loads with real transport'
  )
  check(
    vim.wait(6000, function()
      return #by_method(records(), 'session/set_config_option') >= 6
    end, 10),
    'resumed session defaults finish'
  )
  check(
    vim.wait(6000, function()
      return full_access(resumed.acp_connection)
    end, 10),
    'resumed session uses advertised full-access alias'
  )
  rows = records()
  check(
    #by_method(rows, 'session/new') == 1,
    'resume never creates a phantom session'
  )
  local loads = by_method(rows, 'session/load')
  check(
    #loads == 1 and loads[1].params.sessionId == 'saved-fixture-id',
    'exact saved ID loaded: ' .. vim.inspect(loads)
  )
  check(
    resumed.acp_connection.session_id == 'saved-fixture-id',
    'saved identity retained'
  )
  local missing = assert(
    Chat.new({ adapter = 'codex', acp_session_id = 'missing-fixture-id' })
  )
  chats[#chats + 1] = missing
  check(
    vim.wait(6000, function()
      return missing._lpke_acp_session_unavailable_notified ~= nil
    end, 10),
    'real load error reaches custom recovery'
  )
  check(
    missing._lpke_acp_session_unavailable_notified:find(
      'Fixture session missing',
      1,
      true
    ),
    'server error text retained'
  )
  check(
    missing.acp_session_id == 'missing-fixture-id',
    'failed resume retains requested ID'
  )
  check(
    not missing.acp_connection.session_id,
    'failed resume does not masquerade as connected session'
  )
  check(
    #by_method(records(), 'session/new') == 1,
    'failed resume never falls back to unrelated new session'
  )
  for _, unavailable in ipairs({ 'no-load', 'missing-load' }) do
    profile = unavailable
    local unavailable_id = unavailable .. '-saved-id'
    local blocked =
      assert(Chat.new({ adapter = 'codex', acp_session_id = unavailable_id }))
    chats[#chats + 1] = blocked
    check(
      vim.wait(6000, function()
        return blocked._lpke_acp_session_unavailable_notified ~= nil
      end, 10),
      'unsupported resume is reported: ' .. unavailable
    )
    check(
      blocked.acp_session_id == unavailable_id
        and not blocked.acp_connection.session_id,
      'unsupported resume keeps exact saved ID'
    )
    check(
      #by_method(records(), 'session/new') == 1,
      'unsupported resume never creates another session'
    )
  end

  profile = 'slow-load'
  local loading = assert(Chat.new({
    adapter = 'codex',
    acp_session_id = 'slow-saved-id',
    save_id = 'transport-' .. vim.fn.fnamemodify(fixture, ':t'),
  }))
  chats[#chats + 1] = loading
  check(
    vim.wait(6000, function()
      return loading.acp_connection and loading.acp_connection._loading_session
    end, 10),
    'slow load is in flight'
  )
  loading:add_context(
    { content = 'Fixture unsent context' },
    { source = 'fixture', id = '<fixture-context />' }
  )
  api.nvim_buf_set_lines(
    loading.bufnr,
    -1,
    -1,
    false,
    { '  NEW IMPORTANT FOLLOWUP  ', '', 'tail' }
  )
  api.nvim_set_current_win(loading.ui.winnr)
  api.nvim_win_set_cursor(0, { api.nvim_buf_line_count(loading.bufnr), 2 })
  local draft = require('lpke.plugins.ai.helpers.chat_draft').read(loading)
  local before_prompts = #by_method(records(), 'session/prompt')
  loading:submit()
  check(
    #by_method(records(), 'session/prompt') == before_prompts,
    'loading veto occurs before prompt is sent'
  )
  local options_ready = false
  lifecycle.ensure_chat_ready(loading, function()
    check(
      not loading._lpke_session_preparing,
      'option selection waits for whole session transaction'
    )
    check(
      loading.acp_connection:get_models().currentModelId == 'gpt-6.1-sol',
      'model defaults precede option selection'
    )
    loading.acp_connection:set_config_option('thought_level', 'low')
    options_ready = true
  end)
  check(
    vim.wait(6000, function()
      return options_ready
    end, 10),
    'option picker readiness callback finishes'
  )
  check(
    require('lpke.plugins.ai.helpers.chat_draft').read(loading) == draft,
    'replay preserves exact typed draft and context rows'
  )
  check(
    api.nvim_win_get_cursor(loading.ui.winnr)[2] == 2,
    'replay preserves draft cursor column'
  )
  check(#loading.context_items == 1, 'replay retains unsent context metadata')
  check(
    table
      .concat(api.nvim_buf_get_lines(loading.bufnr, 0, -1, false), '\n')
      :find('Saved original answer', 1, true),
    'saved transcript remains alongside draft'
  )
  local context_messages = vim.tbl_filter(function(message)
    return message.content == 'Fixture unsent context'
  end, loading.messages)
  check(#context_messages == 1, 'replay retains one unsent context message')
  loading:submit()
  check(
    vim.wait(6000, function()
      return #by_method(records(), 'session/prompt') == before_prompts + 1
        and not loading.current_request
    end, 10),
    'preserved followup sends normally once ready'
  )

  local direct = assert(Chat.new({ adapter = 'codex' }))
  chats[#chats + 1] = direct
  check(
    vim.wait(6000, function()
      return direct.acp_connection
        and direct.acp_connection:is_connected()
        and not lifecycle.is_preparing(direct)
    end, 10),
    'direct resume source is ready'
  )
  local typed, typed_error, direct_draft
  before_prompts = #by_method(records(), 'session/prompt')
  vim.defer_fn(function()
    local ok, err = pcall(function()
      check(lifecycle.is_preparing(direct), 'direct load holds readiness guard')
      direct:add_context(
        { content = 'Direct unsent context' },
        { source = 'fixture', id = '<direct-context />' }
      )
      api.nvim_buf_set_lines(direct.bufnr, -1, -1, false, {
        '  FOLLOWUP DURING DIRECT RESUME  ',
        '',
        'tail',
      })
      api.nvim_win_set_cursor(direct.ui.winnr, {
        api.nvim_buf_line_count(direct.bufnr),
        2,
      })
      direct_draft = require('lpke.plugins.ai.helpers.chat_draft').read(direct)
      direct:submit()
      local concurrent, busy =
        require('lpke.plugins.ai.helpers.history_acp').resume_session_into_chat(
          direct,
          'overlapping-saved-id'
        )
      check(
        not concurrent and type(busy) == 'string' and busy:find('busy', 1, true),
        'nested explicit resume returns busy without waiting on outer load'
      )
      check(
        direct.acp_connection.session_id == 'direct-saved-id',
        'busy resume cannot replace the active load identity'
      )
      typed = true
    end)
    if not ok then
      typed_error = err
    end
  end, 50)
  local loaded, load_error =
    require('lpke.plugins.ai.helpers.history_acp').resume_session_into_chat(
      direct,
      'direct-saved-id'
    )
  check(loaded, load_error or 'direct public resume succeeds')
  check(
    typed and not typed_error,
    typed_error or 'followup composed during direct load'
  )
  check(
    #by_method(records(), 'session/prompt') == before_prompts,
    'direct load vetoes prompt until defaults and replay finish'
  )
  check(
    require('lpke.plugins.ai.helpers.chat_draft').read(direct) == direct_draft,
    'direct resume preserves exact draft and context rows'
  )
  check(#direct.context_items == 1, 'direct resume preserves context metadata')
  check(
    api.nvim_win_get_cursor(direct.ui.winnr)[2] == 2,
    'direct resume preserves draft cursor'
  )
  check(
    direct.acp_session_id == 'direct-saved-id',
    'direct resume remembers exact session'
  )
  check(
    #vim.tbl_filter(function(row)
        return row.params.sessionId == 'overlapping-saved-id'
      end, by_method(records(), 'session/load')) == 0,
    'busy resume never sends a second load'
  )
  direct:submit()
  check(
    vim.wait(6000, function()
      return #by_method(records(), 'session/prompt') == before_prompts + 1
        and not direct.current_request
    end, 10),
    'direct followup sends after readiness'
  )

  local replaced = assert(Chat.new({
    adapter = 'codex',
    acp_session_id = 'replaced-saved-id',
  }))
  chats[#chats + 1] = replaced
  check(
    vim.wait(6000, function()
      return replaced.acp_connection
        and replaced.acp_connection._loading_session
    end, 10),
    'connection replacement starts during load'
  )
  local old_conn, stale_callback, replacement_ready =
    replaced.acp_connection, false, false
  lifecycle.ensure_chat_connection(replaced, function()
    stale_callback = true
  end)
  lifecycle.ensure_chat_ready(replaced, function()
    stale_callback = true
  end)
  lifecycle.suspend_chat(replaced, {
    close_chat = false,
    cancel_prompt = false,
    delay_ms = 20,
  })
  lifecycle.ensure_chat_connection(replaced, function()
    replacement_ready = true
  end)
  check(
    vim.wait(6000, function()
      return replacement_ready
    end, 10),
    'replacement connection completes readiness'
  )
  check(
    replaced.acp_connection ~= old_conn and not stale_callback,
    'old session and connection callbacks cannot act on same-adapter replacement'
  )
  check(
    not lifecycle.is_preparing(replaced),
    'old completion cannot clear replacement transaction'
  )

  profile = 'slow-new'
  local starting = assert(Chat.new({ adapter = 'codex' }))
  chats[#chats + 1] = starting
  starting.opts.cwd = nil
  starting.cwd = fixture
  check(
    vim.wait(6000, function()
      return starting._lpke_session_preparing
        and starting.acp_connection.session_id ~= nil
    end, 10),
    'initial session defaults are in flight'
  )
  api.nvim_buf_set_lines(
    starting.bufnr,
    -1,
    -1,
    false,
    { 'Initial default ordering' }
  )
  local initial_draft =
    require('lpke.plugins.ai.helpers.chat_draft').read(starting)
  before_prompts = #by_method(records(), 'session/prompt')
  starting:submit({ auto_submit = true })
  check(
    #by_method(records(), 'session/prompt') == before_prompts,
    'automatic submit also waits for defaults'
  )
  check(
    require('lpke.plugins.ai.helpers.chat_draft').read(starting)
      == initial_draft,
    'initial readiness veto preserves draft'
  )
  check(
    vim.wait(6000, function()
      return not lifecycle.is_preparing(starting)
    end, 10),
    'initial defaults complete'
  )
  local launches = vim.tbl_filter(function(row)
    return row.event == 'spawn'
  end, records())
  local creations = by_method(records(), 'session/new')
  check(
    launches[#launches].cwd == fixture,
    'chat cwd fallback controls actual process launch'
  )
  check(
    creations[#creations].params.cwd == fixture,
    'chat cwd fallback controls session creation'
  )
  starting:submit()
  check(
    vim.wait(6000, function()
      return #by_method(records(), 'session/prompt') == before_prompts + 1
        and not starting.current_request
    end, 10),
    'initial prompt sends after defaults'
  )
end
vim.schedule(function()
  local ok, err = xpcall(run, debug.traceback)
  config.adapters.acp.codex = factory
  require('lpke.plugins.ai.helpers.title_request').request = original_title
  for _, chat in ipairs(chats) do
    pcall(function()
      chat:close()
    end)
  end
  api.nvim_del_augroup_by_id(group)
  vim.fn.delete(fixture, 'rf')
  if not ok then
    print(err)
    vim.cmd('cquit 1')
  end
  print(
    ('PASS ACP transport: %d checks, real child/session/prompt/resume'):format(
      checks
    )
  )
  vim.cmd('qa!')
end)
