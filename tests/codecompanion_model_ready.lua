-- Full config and a real local ACP peer: controls must wait for load/defaults/replay.
-- run-nvim --headless -u NONE -l tests/codecompanion_model_ready.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.loadplugins = true
dofile('init.lua')
local api = vim.api
local config = require('codecompanion.config')
local adapters = require('codecompanion.adapters')
local Chat = require('codecompanion.interactions.chat')
local lifecycle = require('lpke.plugins.ai.helpers.acp_lifecycle')
local models = require('lpke.plugins.ai.helpers.model_swap')
local ai = require('lpke.plugins.ai.helpers.config')
local draft = require('lpke.plugins.ai.helpers.chat_draft')
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, 'p')
local factory, copilot = config.adapters.acp.codex, config.adapters.http.copilot
local cycle, select_ui = ai.adapters.codex.model_cycle, vim.ui.select
local title_request = require('lpke.plugins.ai.helpers.title_request')
local original_title = title_request.request
local chats, checks, counter = {}, 0, 0
local wire_path, profile
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
local function records(path)
  local rows = {}
  for _, line in ipairs(vim.fn.readfile(path)) do
    rows[#rows + 1] = vim.json.decode(line)
  end
  return rows
end
local function options(path)
  return vim.tbl_filter(function(row)
    return row.method == 'session/set_config_option'
  end, records(path))
end
local function has_model(path, model)
  return vim.iter(options(path)):any(function(row)
    return row.params.configId == 'model' and row.params.value == model
  end)
end
local function settled(chat)
  return chat.acp_connection
    and chat.acp_connection:is_connected()
    and not lifecycle.is_preparing(chat)
end
config.adapters.acp.codex = function()
  local adapter = factory()
  adapter.commands.default = {
    'python3',
    vim.fn.getcwd() .. '/tests/helpers/fake_acp.py',
    wire_path,
    profile,
  }
  return adapter
end
config.adapters.http.copilot = function()
  return adapters.extend('ollama', {
    name = 'copilot',
    schema = {
      model = {
        default = 'claude-sonnet-4.6',
        choices = { ['claude-sonnet-4.6'] = {}, ['gpt-5-mini'] = {} },
      },
    },
  })
end
-- The peer advertises Sol/Other. Keep the actual leader-m callback and cycle logic.
ai.adapters.codex.model_cycle = { 'gpt_6_1_sol', 'other' }
title_request.request = function()
  error('Model-control tests must not invoke a title model')
end
local function loading_chat(kind)
  counter = counter + 1
  profile = kind or 'slow-load'
  wire_path = fixture .. '/wire-' .. counter .. '.jsonl'
  vim.fn.writefile({}, wire_path)
  local session = profile == 'slow-load'
      and ('model-ready-' .. fixture .. '-' .. counter)
    or nil
  local source = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(source)
  local chat = assert(Chat.new({
    buffer_context = {
      bufnr = source,
      filetype = 'lua',
      filename = 'fixture.lua',
      lines = {},
    },
    adapter = 'codex',
    acp_session_id = session,
    save_id = 'model-ready-'
      .. vim.fn.fnamemodify(fixture, ':t')
      .. '-'
      .. counter,
  }))
  chats[#chats + 1] = chat
  local path = wire_path
  wait_for(function()
    return chat.acp_connection
      and (
        profile == 'slow-load' and chat.acp_connection._loading_session
        or profile == 'slow-new'
          and chat._lpke_session_preparing
          and chat.acp_connection.session_id ~= nil
      )
  end, 'fixture reaches active ' .. profile .. ' transaction')
  api.nvim_set_current_win(chat.ui.winnr)
  api.nvim_buf_set_lines(
    chat.bufnr,
    -1,
    -1,
    false,
    { '  Keep exact draft  ', '', 'tail' }
  )
  return chat, path, draft.read(chat), session
end
local function final_choice(chat, path, prompt, session)
  wait_for(function()
    return settled(chat) and models.get_cur_model(chat.bufnr) == 'other'
  end, 'chosen model survives complete session transaction')
  local rows = options(path)
  check(#rows >= 4, 'wire includes defaults followed by chosen model')
  equal(rows[1].params, {
    sessionId = session or chat.acp_connection.session_id,
    configId = 'model',
    value = 'gpt-6.1-sol',
  }, 'configured default model is first')
  local defaults = {}
  for index = 2, 3 do
    defaults[rows[index].params.configId] = rows[index].params.value
  end
  equal(
    defaults,
    { mode = 'full-access', thought_level = 'high' },
    'other session defaults precede user choice'
  )
  equal(rows[#rows].params.value, 'other', 'explicit choice is last on wire')
  equal(
    draft.read(chat),
    prompt,
    'model control preserves exact draft through replay'
  )
  if session then
    equal(
      chat.acp_connection.session_id,
      session,
      'model control retains exact saved session'
    )
    check(
      table
        .concat(api.nvim_buf_get_lines(chat.bufnr, 0, -1, false), '\n')
        :find('Saved original answer', 1, true),
      'replay finishes before model control'
    )
    check(not vim.iter(records(path)):any(function(row)
      return row.method == 'session/new'
    end), 'saved model control creates no unrelated session')
  end
end
local function run()
  local chat, path, prompt, session = loading_chat()
  vim.cmd('Model other')
  check(not has_model(path, 'other'), ':Model sends no premature model option')
  final_choice(chat, path, prompt, session)

  chat, path, prompt, session = loading_chat()
  local map = vim.fn.maparg((vim.g.mapleader or '\\') .. 'm', 'n', false, true)
  check(type(map.callback) == 'function', 'actual leader-m callback exists')
  map.callback()
  check(
    not has_model(path, 'other'),
    'leader-m sends no premature model option'
  )
  final_choice(chat, path, prompt, session)

  chat, path, prompt, session = loading_chat()
  local model_pickers = 0
  vim.ui.select = function(items, opts, callback)
    if opts.prompt == 'Select Adapter' then
      callback('codex')
    elseif opts.prompt == 'Select Model' then
      model_pickers = model_pickers + 1
      check(settled(chat), 'ga model picker opens only after full readiness')
      check(#options(path) >= 3, 'ga picker sees completed session defaults')
      for _, item in ipairs(items) do
        if item.modelId == 'other' then
          callback(item)
          return
        end
      end
      error('Other model absent after readiness')
    else
      error('Unexpected picker ' .. tostring(opts.prompt))
    end
  end
  config.interactions.chat.keymaps.change_adapter.callback(chat)
  equal(model_pickers, 0, 'same-adapter ga defers model picker during load')
  final_choice(chat, path, prompt, session)
  equal(model_pickers, 1, 'ga opens its model picker exactly once')
  vim.ui.select = select_ui

  chat, path, prompt, session = loading_chat('slow-new')
  vim.cmd('Model other')
  check(
    not has_model(path, 'other'),
    'new-session defaults also defer model change'
  )
  final_choice(chat, path, prompt, session)

  chat, path = loading_chat()
  vim.cmd('Model other')
  vim.cmd('Model sol')
  wait_for(function()
    return settled(chat)
  end, 'superseded controls finish readiness')
  vim.wait(150, function()
    return false
  end)
  equal(
    models.get_cur_model(chat.bufnr),
    'gpt-6.1-sol',
    'latest pending model command wins'
  )
  check(
    not has_model(path, 'other'),
    'superseded pending choice never reaches wire'
  )

  chat, path, prompt, session = loading_chat()
  model_pickers = 0
  vim.ui.select = function(_, opts, callback)
    if opts.prompt == 'Select Adapter' then
      callback('codex')
    elseif opts.prompt == 'Select Model' then
      model_pickers = model_pickers + 1
    else
      error('Unexpected picker ' .. tostring(opts.prompt))
    end
  end
  config.interactions.chat.keymaps.change_adapter.callback(chat)
  vim.cmd('Model other')
  final_choice(chat, path, prompt, session)
  equal(
    model_pickers,
    0,
    'new model command supersedes pending same-adapter picker'
  )
  vim.ui.select = select_ui

  chat, path = loading_chat()
  local warnings, original_notify = {}, vim.notify
  vim.notify = function(message, level, opts)
    warnings[#warnings + 1] = message
    return original_notify(message, level, opts)
  end
  vim.cmd('Model unavailable-fixture-model')
  check(
    not has_model(path, 'unavailable-fixture-model'),
    'unknown model is not sent before metadata arrives'
  )
  wait_for(function()
    return settled(chat)
      and vim.iter(warnings):any(function(message)
        return message:find('not available', 1, true) ~= nil
      end)
  end, 'late model metadata produces unavailable-model warning')
  vim.notify = original_notify
  equal(
    models.get_cur_model(chat.bufnr),
    'gpt-6.1-sol',
    'late unavailable model retains configured default'
  )
  check(
    not has_model(path, 'unavailable-fixture-model'),
    'late unavailable model never reaches peer'
  )

  chat, path = loading_chat()
  vim.cmd('Model other')
  vim.cmd('Adapter copilot')
  wait_for(function()
    return chat.adapter.name == 'copilot'
  end, 'adapter switch completes')
  vim.cmd('Model gpt5m')
  equal(
    models.get_cur_model(chat.bufnr),
    'gpt-5-mini',
    'HTTP model changes remain immediate'
  )
  vim.wait(600, function()
    return false
  end)
  equal(
    chat.adapter.name,
    'copilot',
    'old readiness callback cannot restore replaced adapter'
  )
  equal(
    models.get_cur_model(chat.bufnr),
    'gpt-5-mini',
    'old ACP choice cannot mutate current HTTP model'
  )
  check(
    not has_model(path, 'other'),
    'replaced adapter drops its pending model choice'
  )

  chat, path = loading_chat()
  vim.cmd('Model other')
  local old_connection = chat.acp_connection
  lifecycle.suspend_chat(chat, { stop_request = true, close_chat = false })
  local reconnected = false
  lifecycle.ensure_chat_connection(chat, function()
    reconnected = true
  end)
  wait_for(function()
    return reconnected and settled(chat)
  end, 'replacement connection becomes ready')
  check(
    chat.acp_connection ~= old_connection,
    'reconnection uses a different native connection'
  )
  equal(
    models.get_cur_model(chat.bufnr),
    'gpt-6.1-sol',
    'old choice cannot mutate replacement connection'
  )
  check(
    not has_model(path, 'other'),
    'replaced connection drops pending model choice'
  )

  chat, path = loading_chat()
  vim.cmd('Model other')
  local bufnr = chat.bufnr
  chat:close()
  vim.wait(600, function()
    return false
  end)
  equal(
    require('codecompanion').buf_get_chat(bufnr),
    nil,
    'closing chat cannot be undone by pending choice'
  )
  check(not has_model(path, 'other'), 'closed chat drops pending model choice')
end
vim.schedule(function()
  local ok, err = xpcall(run, debug.traceback)
  config.adapters.acp.codex, config.adapters.http.copilot = factory, copilot
  ai.adapters.codex.model_cycle, vim.ui.select = cycle, select_ui
  title_request.request = original_title
  for _, chat in ipairs(chats) do
    pcall(function()
      require('lpke.plugins.ai.helpers.drafts').delete_for_buffer(chat.bufnr)
      if chat.opts.save_id then
        require('codecompanion').extensions.history.delete_chat(
          chat.opts.save_id
        )
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
    ('PASS model readiness: %d checks, actual slow ACP controls and replacement guards'):format(
      checks
    )
  )
  vim.cmd('qa!')
end)
