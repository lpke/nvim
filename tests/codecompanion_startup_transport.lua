-- Complete production startup path with a real local ACP peer and no AI service.
-- run-nvim --headless -u NONE -l tests/codecompanion_startup_transport.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.loadplugins = true
dofile('init.lua')
local api = vim.api
local cc, config = require('codecompanion'), require('codecompanion.config')
local lifecycle = require('lpke.plugins.ai.helpers.acp_lifecycle')
local startup = require('lpke.plugins.ai.helpers.startup_codex')
local extensions = require('lpke.core.local_extensions')
local title_request = require('lpke.plugins.ai.helpers.title_request')
local factory, call, title =
  config.adapters.acp.codex, extensions.call, title_request.request
local original_notify = vim.notify
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, 'p')
local chats, notices, hooks = {}, {}, {}
local checks, counter = 0, 0
local profile, wire, delegated
local function check(value, label)
  checks = checks + 1
  assert(value, label)
end
local function equal(actual, expected, label)
  check(vim.deep_equal(actual, expected), label .. '\n' .. vim.inspect(actual))
end
local function wait_for(predicate, label)
  check(vim.wait(6000, predicate, 10), label)
end
local function rows(path)
  local result = {}
  for _, line in ipairs(vim.fn.readfile(path)) do
    result[#result + 1] = vim.json.decode(line)
  end
  return result
end
local function requests(path, method)
  return vim.tbl_filter(function(row)
    return row.method == method
  end, rows(path))
end
config.adapters.acp.codex = function()
  local adapter = factory()
  adapter.commands.default = {
    'python3',
    vim.fn.getcwd() .. '/tests/helpers/fake_acp.py',
    wire,
    profile,
  }
  return adapter
end
extensions.call = function(name, ...)
  if name == 'startup_chat' then
    local id = ...
    local current = cc.buf_get_chat(0)
    hooks[#hooks + 1] = { id = id, chat = current }
    if id then
      check(
        current.opts.acp_connection_only,
        'integration receives session before automatic load'
      )
      equal(
        current.opts.acp_session_id,
        id,
        'integration sees exact constructor session ID'
      )
    end
    return delegated
  end
  return call(name, ...)
end
title_request.request = function()
  error('Startup restore must not invoke a title model')
end
vim.notify = function(message, level, opts)
  notices[#notices + 1] = message
  return original_notify(message, level, opts)
end
local function open(id, peer, handled)
  counter = counter + 1
  profile, delegated = peer or 'slow-load', handled or false
  wire = fixture .. '/wire-' .. counter .. '.jsonl'
  vim.fn.writefile({}, wire)
  local source = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(source)
  startup.open(id)
  local chat = assert(cc.buf_get_chat(0))
  chats[#chats + 1] = chat
  equal(#api.nvim_list_tabpages(), 1, 'startup keeps one tab')
  equal(#api.nvim_list_wins(), 1, 'startup replaces source window fullscreen')
  equal(api.nvim_win_get_buf(0), chat.bufnr, 'startup focuses returned chat')
  return chat, wire
end
local function run()
  local id = 'startup-exact-' .. vim.fn.fnamemodify(fixture, ':t')
  local chat, path = open(id)
  equal(
    chat.acp_session_id,
    id,
    'target identity exists before eager initialization'
  )
  wait_for(function()
    return chat.acp_connection and chat.acp_connection._loading_session
  end, 'startup target enters exact session/load')
  api.nvim_buf_set_lines(
    chat.bufnr,
    -1,
    -1,
    false,
    { '  Preserve startup draft  ', '', 'tail' }
  )
  local prompt = require('lpke.plugins.ai.helpers.chat_draft').read(chat)
  wait_for(function()
    return chat._lpke_acp_session_restored == id
      and not lifecycle.is_preparing(chat)
  end, 'startup exact replay/default transaction completes')
  equal(
    #requests(path, 'session/new'),
    0,
    'exact startup never creates a phantom session'
  )
  equal(#requests(path, 'session/load'), 1, 'exact startup loads target once')
  equal(
    requests(path, 'session/load')[1].params.sessionId,
    id,
    'wire uses required startup thread'
  )
  equal(
    #requests(path, 'session/set_config_option'),
    3,
    'startup applies defaults once'
  )
  equal(
    requests(path, 'session/set_config_option')[1].params.configId,
    'model',
    'startup defaults remain model-first'
  )
  equal(
    chat.acp_connection:get_models().currentModelId,
    'gpt-6.1-sol',
    'startup keeps configured model'
  )
  equal(#requests(path, 'session/prompt'), 0, 'startup replay sends no prompt')
  equal(
    require('lpke.plugins.ai.helpers.chat_draft').read(chat),
    prompt,
    'startup replay preserves typed draft'
  )
  local visible =
    table.concat(api.nvim_buf_get_lines(chat.bufnr, 0, -1, false), '\n')
  check(
    visible:find('Saved original prompt', 1, true),
    'startup shows saved user transcript'
  )
  check(
    visible:find('Saved original answer', 1, true),
    'startup shows saved assistant transcript'
  )

  chat, path = open('missing-fixture-id')
  wait_for(function()
    return chat._lpke_acp_session_unavailable_notified
      and not chat._lpke_session_preparing
  end, 'missing startup session finishes with visible failure')
  equal(
    chat.acp_session_id,
    'missing-fixture-id',
    'missing startup retains requested ID'
  )
  equal(
    #requests(path, 'session/new'),
    0,
    'missing startup does not create a fallback session'
  )
  equal(
    #requests(path, 'session/load'),
    1,
    'missing startup tries exact load once'
  )
  equal(#requests(path, 'session/prompt'), 0, 'failed startup sends no prompt')
  check(
    vim.iter(notices):any(function(message)
      return message:find('Fixture session missing', 1, true) ~= nil
    end),
    'exact startup RPC error remains visible'
  )

  chat, path = open('unsupported-startup-id', 'missing-load')
  wait_for(function()
    return chat._lpke_acp_session_unavailable_notified
      and not chat._lpke_session_preparing
  end, 'unsupported startup load reports failure')
  equal(
    chat.acp_session_id,
    'unsupported-startup-id',
    'unsupported startup retains requested ID'
  )
  equal(
    #requests(path, 'session/new'),
    0,
    'unsupported startup creates no fallback session'
  )
  equal(
    #requests(path, 'session/load'),
    0,
    'unsupported startup sends no unsupported RPC'
  )

  chat, path = open('delegated-startup-id', 'slow-load', true)
  wait_for(function()
    return chat.acp_connection
      and chat.acp_connection:is_ready()
      and not chat._lpke_session_preparing
  end, 'delegated startup establishes transport only')
  equal(
    chat.opts.acp_connection_only,
    true,
    'owner retains control over session establishment'
  )
  equal(
    #requests(path, 'session/new'),
    0,
    'delegated startup creates no session'
  )
  equal(
    #requests(path, 'session/load'),
    0,
    'delegated startup does not bypass owner by loading'
  )
  equal(
    #requests(path, 'session/prompt'),
    0,
    'delegated startup sends no prompt'
  )
  equal(
    chat._lpke_acp_session_restored,
    nil,
    'delegated startup performs no shared replay'
  )

  chat, path = open(nil, 'normal')
  wait_for(function()
    return chat.acp_connection
      and chat.acp_connection:is_connected()
      and not lifecycle.is_preparing(chat)
  end, 'blank startup establishes a normal new session')
  equal(
    #requests(path, 'session/new'),
    1,
    'blank startup creates exactly one session'
  )
  equal(#requests(path, 'session/load'), 0, 'blank startup has no exact load')
  equal(
    #requests(path, 'session/prompt'),
    0,
    'blank startup sends no hidden prompt'
  )
  equal(hooks[#hooks].id, nil, 'blank startup still invokes optional hook')
end
vim.schedule(function()
  local ok, err = xpcall(run, debug.traceback)
  config.adapters.acp.codex, extensions.call, title_request.request, vim.notify =
    factory, call, title, original_notify
  for _, chat in ipairs(chats) do
    pcall(function()
      require('lpke.plugins.ai.helpers.drafts').delete_for_buffer(chat.bufnr)
      if chat.opts.save_id then
        cc.extensions.history.delete_chat(chat.opts.save_id)
      end
      chat:close()
    end)
  end
  vim.fn.delete(fixture, 'rf')
  if not ok then
    print(err)
    vim.cmd('cquit 1')
  end
  print(
    ('PASS startup transport: %d checks, exact thread/no phantom session/delegation/failures'):format(
      checks
    )
  )
  vim.cmd('qa!')
end)
