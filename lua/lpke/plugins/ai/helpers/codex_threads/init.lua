local M = {}

local api = vim.api
local client_module = require('lpke.plugins.ai.helpers.codex_threads.client')
local formatter = require('lpke.plugins.ai.helpers.codex_threads.format')
local helpers = require('lpke.core.helpers')

local DASHBOARD_POLL_MS = 1500
local DASHBOARD_READ_CONCURRENCY = 6
local DASHBOARD_LIVE_THREADS = 10
local THREAD_POLL_MS = 600
local MAX_THREADS = 500
local SUBAGENT_SOURCE_KINDS = {
  'subAgent',
  'subAgentReview',
  'subAgentCompact',
  'subAgentThreadSpawn',
  'subAgentOther',
}

local dashboards = {}
local hidden_completions_by_scope = {}
local thread_views = {}
local acp_tool_calls = {}
local live_prompts = {}
local setup_done = false

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, {
    title = 'Codex subagents',
  })
end

local function valid_buffer(bufnr)
  return type(bufnr) == 'number' and api.nvim_buf_is_valid(bufnr)
end

local function stop_timer(state)
  if not state.timer then
    return
  end
  state.timer:stop()
  if not state.timer:is_closing() then
    state.timer:close()
  end
  state.timer = nil
end

local function find_window(bufnr)
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if api.nvim_win_is_valid(winid) then
      return winid
    end
  end
end

local function show_buffer(bufnr)
  local winid = find_window(bufnr)
  if winid then
    api.nvim_set_current_win(winid)
    return winid
  end

  vim.cmd('botright vsplit')
  winid = api.nvim_get_current_win()
  api.nvim_win_set_buf(winid, bufnr)
  vim.cmd('vertical resize 88')
  vim.wo[winid].wrap = true
  vim.wo[winid].linebreak = true
  vim.wo[winid].conceallevel = 2
  return winid
end

local function replace_lines(bufnr, lines)
  if not valid_buffer(bufnr) then
    return
  end

  local buffer_lines = {}
  for _, line in ipairs(lines) do
    for _, part in ipairs(vim.split(tostring(line), '\n', { plain = true })) do
      table.insert(buffer_lines, (part:gsub('\r$', '')))
    end
  end

  local winid = find_window(bufnr)
  local cursor = winid and api.nvim_win_get_cursor(winid) or nil
  local old_count = api.nvim_buf_line_count(bufnr)
  local was_at_end = cursor and cursor[1] >= old_count

  vim.bo[bufnr].modifiable = true
  api.nvim_buf_set_lines(bufnr, 0, -1, false, buffer_lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false

  if not (winid and cursor) then
    return
  end

  local new_count = api.nvim_buf_line_count(bufnr)
  local row = was_at_end and new_count or math.min(cursor[1], new_count)
  pcall(api.nvim_win_set_cursor, winid, { math.max(1, row), cursor[2] })
end

local function scratch_buffer(name)
  local bufnr = api.nvim_create_buf(false, true)
  pcall(api.nvim_buf_set_name, bufnr, name)
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].undofile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = 'markdown'
  return bufnr
end

local function start_polling(state, interval_ms, refresh)
  stop_timer(state)
  state.timer = vim.uv.new_timer()
  state.timer:start(
    interval_ms,
    interval_ms,
    vim.schedule_wrap(function()
      if not valid_buffer(state.bufnr) then
        stop_timer(state)
        return
      end
      refresh(state)
    end)
  )
end

local function current_parent_id()
  local ok_chat, Chat = pcall(require, 'codecompanion.interactions.chat')
  local chat = ok_chat and Chat.buf_get_chat(0) or nil

  if not chat then
    local ok_codecompanion, codecompanion = pcall(require, 'codecompanion')
    if ok_codecompanion and type(codecompanion.last_chat) == 'function' then
      chat = codecompanion.last_chat()
    end
  end

  if
    not chat
    or not chat.adapter
    or chat.adapter.type ~= 'acp'
    or chat.adapter.name ~= 'codex'
  then
    return nil
  end

  local ok_lifecycle, lifecycle =
    pcall(require, 'lpke.plugins.ai.helpers.acp_lifecycle')
  if not ok_lifecycle then
    return nil
  end
  return lifecycle.get_session_id(chat)
end

local function scope_key(scope)
  return table.concat({ scope.host, scope.parent_id or '*' }, ':')
end

local function thread_key(host, thread_id)
  return host .. ':' .. thread_id
end

local function scope_choices()
  local choices = {}
  local parent_id = current_parent_id()
  if parent_id then
    table.insert(choices, {
      label = 'Local · current CodeCompanion chat',
      host = 'local',
      parent_id = parent_id,
    })
  end
  table.insert(choices, {
    label = 'Local · all subagents',
    host = 'local',
  })
  table.insert(choices, {
    label = 'Mac · all subagents over ssh mbp',
    host = 'mbp',
  })
  return choices
end

local function sort_threads(threads)
  local function timestamp(thread)
    for _, value in ipairs({
      thread.recencyAt,
      thread.updatedAt,
      thread.createdAt,
    }) do
      if type(value) == 'number' then
        return value
      end
    end
    return 0
  end

  table.sort(threads, function(left, right)
    return timestamp(left) > timestamp(right)
  end)
end

local function list_threads(scope, callback, cursor, collected)
  collected = collected or {}
  local params = {
    cursor = cursor or vim.NIL,
    limit = 100,
    sortKey = 'recency_at',
    sortDirection = 'desc',
    sourceKinds = SUBAGENT_SOURCE_KINDS,
  }
  if scope.parent_id then
    params.ancestorThreadId = scope.parent_id
  end

  client_module
    .get(scope.host)
    :request('thread/list', params, function(result, err)
      if err then
        callback(nil, err)
        return
      end

      vim.list_extend(collected, result.data or {})
      if
        result.nextCursor ~= nil
        and result.nextCursor ~= vim.NIL
        and #collected < MAX_THREADS
      then
        list_threads(scope, callback, result.nextCursor, collected)
        return
      end

      sort_threads(collected)
      callback(collected, nil)
    end)
end

local function report_state_error(state, err)
  if state.last_error == err then
    return
  end
  state.last_error = err
  notify(err, vim.log.levels.ERROR)
end

local refresh_dashboard
local open_thread
local render_dashboard

local function detail_version(thread)
  local ok, status = pcall(vim.json.encode, thread.status)
  return table.concat({
    tostring(thread.updatedAt or ''),
    tostring(thread.recencyAt or ''),
    ok and status or '',
  }, ':')
end

local function dashboard_thread(state, summary)
  if state.detail_versions[summary.id] == detail_version(summary) then
    return state.details[summary.id] or summary
  end
  return summary
end

local function visible_dashboard_threads(state)
  local visible = {}
  local hidden_count = 0

  for _, summary in ipairs(state.threads) do
    local marker = formatter.completion_marker(dashboard_thread(state, summary))
    local hidden_marker = state.hidden_completions[summary.id]
    if marker and marker == hidden_marker then
      hidden_count = hidden_count + 1
    else
      if hidden_marker then
        state.hidden_completions[summary.id] = nil
      end
      table.insert(visible, summary)
    end
  end

  return visible, hidden_count
end

local function hide_completed_runs(state)
  local hidden = 0
  for _, summary in ipairs(state.threads) do
    local marker = formatter.completion_marker(dashboard_thread(state, summary))
    if marker and state.hidden_completions[summary.id] ~= marker then
      state.hidden_completions[summary.id] = marker
      hidden = hidden + 1
    end
  end
  render_dashboard(state)
  notify(
    hidden > 0 and ('Hid ' .. hidden .. ' completed run(s)')
      or 'No new completed runs to hide'
  )
end

local function show_all_runs(state)
  local restored = 0
  for thread_id in pairs(state.hidden_completions) do
    state.hidden_completions[thread_id] = nil
    restored = restored + 1
  end
  render_dashboard(state)
  notify(
    restored > 0 and ('Restored ' .. restored .. ' run(s)')
      or 'All runs are already visible'
  )
end

local function set_dashboard_keymaps(state)
  helpers.keymap_set_multi({
    {
      'n!',
      '<CR>',
      function()
        local line = api.nvim_win_get_cursor(0)[1]
        local thread = state.line_threads[line]
        if thread then
          open_thread(
            state.scope.host,
            thread.id,
            thread,
            state.executions[thread.id],
            state.execution_errors[thread.id]
          )
        end
      end,
      { buffer = state.bufnr, desc = 'Codex subagents: Inspect thread' },
    },
    {
      'n!',
      'h',
      function()
        hide_completed_runs(state)
      end,
      { buffer = state.bufnr, desc = 'Codex subagents: Hide completed so far' },
    },
    {
      'n!',
      'u',
      function()
        show_all_runs(state)
      end,
      { buffer = state.bufnr, desc = 'Codex subagents: Show all runs' },
    },
    {
      'n!',
      'r',
      function()
        refresh_dashboard(state, true)
      end,
      { buffer = state.bufnr, desc = 'Codex subagents: Refresh' },
    },
    {
      'n!',
      's',
      function()
        M.open()
      end,
      { buffer = state.bufnr, desc = 'Codex subagents: Change source' },
    },
    {
      'n!',
      'q',
      function()
        api.nvim_buf_delete(state.bufnr, { force = true })
      end,
      { buffer = state.bufnr, desc = 'Codex subagents: Close' },
    },
  })
end

local function execution_metadata(result)
  return {
    activePermissionProfile = result.activePermissionProfile,
    approvalPolicy = result.approvalPolicy,
    cwd = result.cwd,
    model = result.model,
    modelProvider = result.modelProvider,
    multiAgentMode = result.multiAgentMode,
    reasoningEffort = result.reasoningEffort,
    sandbox = result.sandbox,
    serviceTier = result.serviceTier,
  }
end

render_dashboard = function(state)
  if not valid_buffer(state.bufnr) then
    return
  end

  local threads, hidden_count = visible_dashboard_threads(state)
  local lines, line_threads = formatter.dashboard(
    state.scope,
    threads,
    state.details,
    state.parents,
    state.detail_errors,
    live_prompts,
    state.executions,
    state.execution_errors,
    hidden_count
  )
  state.line_threads = line_threads
  replace_lines(state.bufnr, lines)
end

local function schedule_dashboard_render(state)
  if state.render_pending then
    return
  end
  state.render_pending = true
  vim.defer_fn(function()
    state.render_pending = false
    render_dashboard(state)
  end, 50)
end

local function capture_acp_tool_call(tool_call)
  if type(tool_call) ~= 'table' or type(tool_call.toolCallId) ~= 'string' then
    return
  end

  local captured = acp_tool_calls[tool_call.toolCallId] or {}
  if type(tool_call.rawInput) == 'table' then
    captured.raw_input = captured.raw_input or {}
    for key, value in pairs(tool_call.rawInput) do
      if value ~= vim.NIL then
        captured.raw_input[key] = value
      end
    end
  end
  acp_tool_calls[tool_call.toolCallId] = captured

  local raw_input = captured.raw_input
  if
    raw_input
    and type(raw_input.prompt) == 'string'
    and raw_input.prompt ~= ''
    and type(raw_input.receiverThreadIds) == 'table'
  then
    for _, thread_id in ipairs(raw_input.receiverThreadIds) do
      if type(thread_id) == 'string' then
        live_prompts[thread_id] = raw_input.prompt
      end
    end
    for _, state in pairs(dashboards) do
      if state.scope.host == 'local' then
        schedule_dashboard_render(state)
      end
    end
  end

  if tool_call.status == 'completed' or tool_call.status == 'failed' then
    acp_tool_calls[tool_call.toolCallId] = nil
  end
end

local function patch_codecompanion_acp_tools()
  local handler = require('codecompanion.interactions.chat.acp.handler')
  if handler._lpke_codex_subagent_capture then
    return
  end

  handler._lpke_codex_subagent_capture = true
  local original_process_tool_call = handler.process_tool_call
  handler.process_tool_call = function(self, tool_call)
    capture_acp_tool_call(tool_call)
    return original_process_tool_call(self, tool_call)
  end
end

local function hydrate_dashboard(state, force, callback)
  local tasks = {}
  local task_keys = {}

  local function add_task(kind, thread_id, version)
    if not thread_id then
      return
    end
    local key = kind .. ':' .. thread_id
    if task_keys[key] then
      return
    end
    task_keys[key] = true
    table.insert(tasks, {
      id = thread_id,
      kind = kind,
      version = version,
    })
  end

  for index, thread in ipairs(state.threads) do
    local marker = formatter.completion_marker(dashboard_thread(state, thread))
    local is_hidden = marker and marker == state.hidden_completions[thread.id]
    if not is_hidden then
      local version = detail_version(thread)
      local refresh_child = force
        or state.scope.parent_id ~= nil
        or index <= DASHBOARD_LIVE_THREADS
        or not state.details[thread.id]
        or state.detail_versions[thread.id] ~= version
      if refresh_child then
        add_task('child', thread.id, version)
      end

      if
        not state.execution_requested[thread.id]
        or (force and state.execution_errors[thread.id])
      then
        state.execution_requested[thread.id] = true
        add_task('execution', thread.id)
      end

      local parent_id = formatter.parent_thread_id(thread)
      if
        parent_id
        and (
          force
          or state.scope.parent_id ~= nil
          or refresh_child
          or not state.parents[parent_id]
        )
      then
        add_task('parent', parent_id)
      end
    end
  end

  if #tasks == 0 then
    callback()
    return
  end

  local active = 0
  local next_index = 1
  local remaining = #tasks
  local launch

  local function complete_task(task, result, err)
    active = active - 1
    remaining = remaining - 1

    if task.kind == 'child' then
      if result and result.thread then
        state.details[task.id] = result.thread
        state.detail_versions[task.id] = task.version
        state.detail_errors[task.id] = nil
      elseif err then
        state.detail_errors[task.id] = err
      end
    elseif task.kind == 'parent' and result and result.thread then
      state.parents[task.id] = result.thread
    elseif task.kind == 'execution' then
      if result then
        state.executions[task.id] = execution_metadata(result)
        state.execution_errors[task.id] = nil
      elseif err then
        state.execution_errors[task.id] = err
      end
    end

    schedule_dashboard_render(state)
    if remaining == 0 then
      if state.execution_client then
        state.execution_client:stop()
        state.execution_client = nil
      end
      callback()
      return
    end
    launch()
  end

  launch = function()
    while active < DASHBOARD_READ_CONCURRENCY and next_index <= #tasks do
      local task = tasks[next_index]
      next_index = next_index + 1
      active = active + 1
      local client = client_module.get(state.scope.host)
      local method = 'thread/read'
      local params = {
        threadId = task.id,
        includeTurns = true,
      }
      if task.kind == 'execution' then
        state.execution_client = state.execution_client
          or client_module.Client.new(state.scope.host)
        client = state.execution_client
        method = 'thread/resume'
        params = { threadId = task.id }
      end
      client:request(method, params, function(result, err)
        complete_task(task, result, err)
      end)
    end
  end

  launch()
end

refresh_dashboard = function(state, force)
  if state.inflight or not valid_buffer(state.bufnr) then
    return
  end
  state.inflight = true

  list_threads(state.scope, function(threads, err)
    if err then
      state.inflight = false
      report_state_error(state, err)
      if #state.threads == 0 then
        replace_lines(state.bufnr, {
          '# Codex subagents',
          '',
          'Source: `' .. state.scope.label .. '`',
          '',
          'Error:',
          '',
          err,
        })
      end
      return
    end

    state.last_error = nil
    state.threads = threads
    render_dashboard(state)
    hydrate_dashboard(state, force, function()
      state.inflight = false
      render_dashboard(state)
    end)
  end)
end

local function open_dashboard(scope)
  local key = scope_key(scope)
  local state = dashboards[key]
  if state and valid_buffer(state.bufnr) then
    show_buffer(state.bufnr)
    refresh_dashboard(state, true)
    return
  end

  state = {
    bufnr = scratch_buffer('[Codex subagents] ' .. scope.label),
    detail_errors = {},
    detail_versions = {},
    details = {},
    execution_client = nil,
    execution_errors = {},
    execution_requested = {},
    executions = {},
    inflight = false,
    hidden_completions = hidden_completions_by_scope[key] or {},
    key = key,
    last_error = nil,
    line_threads = {},
    parents = {},
    render_pending = false,
    scope = scope,
    threads = {},
  }
  hidden_completions_by_scope[key] = state.hidden_completions
  dashboards[key] = state
  vim.b[state.bufnr].codex_subagent_dashboard = true
  set_dashboard_keymaps(state)
  api.nvim_create_autocmd('BufWipeout', {
    buffer = state.bufnr,
    once = true,
    callback = function()
      stop_timer(state)
      if state.execution_client then
        state.execution_client:stop()
        state.execution_client = nil
      end
      dashboards[key] = nil
    end,
  })

  replace_lines(state.bufnr, {
    '# Codex subagents',
    '',
    'Connecting to `' .. scope.label .. '`...',
  })
  show_buffer(state.bufnr)
  refresh_dashboard(state)
  start_polling(state, DASHBOARD_POLL_MS, refresh_dashboard)
end

local function refresh_thread(state)
  if state.inflight or not valid_buffer(state.bufnr) then
    return
  end
  state.inflight = true

  client_module.get(state.host):request('thread/read', {
    threadId = state.thread_id,
    includeTurns = true,
  }, function(result, err)
    state.inflight = false
    if err then
      report_state_error(state, err)
      if not state.thread then
        replace_lines(state.bufnr, {
          '# Codex subagent',
          '',
          'Thread: `' .. state.thread_id .. '`',
          '',
          'Error:',
          '',
          err,
        })
      end
      return
    end

    state.last_error = nil
    state.thread = result.thread
    local ok, encoded = pcall(vim.json.encode, result.thread)
    local fingerprint = ok and vim.fn.sha256(encoded) or tostring(os.time())
    if state.fingerprint == fingerprint then
      return
    end

    state.fingerprint = fingerprint
    replace_lines(
      state.bufnr,
      formatter.thread(
        state.host,
        result.thread,
        state.execution,
        state.execution_error
      )
    )
  end)
end

local function refresh_thread_execution(state)
  if state.execution or state.execution_inflight then
    return
  end
  state.execution_inflight = true
  client_module.get(state.host):request('thread/resume', {
    threadId = state.thread_id,
  }, function(result, err)
    state.execution_inflight = false
    if result then
      state.execution = execution_metadata(result)
      state.execution_error = nil
    elseif err then
      state.execution_error = err
    end
    if valid_buffer(state.bufnr) and state.thread then
      replace_lines(
        state.bufnr,
        formatter.thread(
          state.host,
          state.thread,
          state.execution,
          state.execution_error
        )
      )
    end
  end)
end

local function set_thread_keymaps(state)
  helpers.keymap_set_multi({
    {
      'n!',
      'r',
      function()
        refresh_thread(state)
      end,
      { buffer = state.bufnr, desc = 'Codex subagent: Refresh' },
    },
    {
      'n!',
      's',
      function()
        M.open()
      end,
      { buffer = state.bufnr, desc = 'Codex subagent: Dashboard' },
    },
    {
      'n!',
      'q',
      function()
        api.nvim_buf_delete(state.bufnr, { force = true })
      end,
      { buffer = state.bufnr, desc = 'Codex subagent: Close' },
    },
  })
end

open_thread = function(host, thread_id, summary, execution, execution_error)
  local key = thread_key(host, thread_id)
  local state = thread_views[key]
  if state and valid_buffer(state.bufnr) then
    state.execution = execution or state.execution
    state.execution_error = execution_error or state.execution_error
    show_buffer(state.bufnr)
    refresh_thread_execution(state)
    refresh_thread(state)
    return
  end

  state = {
    bufnr = scratch_buffer('[Codex subagent ' .. host .. '] ' .. thread_id),
    fingerprint = nil,
    host = host,
    inflight = false,
    key = key,
    last_error = nil,
    execution = execution,
    execution_error = execution_error,
    execution_inflight = false,
    thread = summary,
    thread_id = thread_id,
  }
  thread_views[key] = state
  vim.b[state.bufnr].codex_thread_host = host
  vim.b[state.bufnr].codex_thread_id = thread_id
  set_thread_keymaps(state)
  api.nvim_create_autocmd('BufWipeout', {
    buffer = state.bufnr,
    once = true,
    callback = function()
      stop_timer(state)
      thread_views[key] = nil
    end,
  })

  replace_lines(
    state.bufnr,
    formatter.thread(host, summary or {
      id = thread_id,
      status = 'loading',
      turns = {},
    }, execution, execution_error)
  )
  show_buffer(state.bufnr)
  refresh_thread_execution(state)
  refresh_thread(state)
  start_polling(state, THREAD_POLL_MS, refresh_thread)
end

local function choose_scope()
  local choices = scope_choices()
  vim.ui.select(choices, {
    prompt = 'Codex subagents',
    kind = 'lpke.codex_subagents.scope',
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      open_dashboard(choice)
    end
  end)
end

function M.open(scope_name)
  if not scope_name or scope_name == '' then
    choose_scope()
    return
  end

  if scope_name == 'current' then
    local parent_id = current_parent_id()
    if not parent_id then
      notify('No active Codex ACP chat with a session id', vim.log.levels.WARN)
      return
    end
    open_dashboard({
      label = 'Local · current CodeCompanion chat',
      host = 'local',
      parent_id = parent_id,
    })
  elseif scope_name == 'local' then
    open_dashboard({ label = 'Local · all subagents', host = 'local' })
  elseif scope_name == 'mbp' or scope_name == 'mac' then
    open_dashboard({
      label = 'Mac · all subagents over ssh mbp',
      host = 'mbp',
    })
  else
    notify('Usage: :CodexAgents [current|local|mbp]', vim.log.levels.WARN)
  end
end

function M.command(cmd)
  M.open(cmd.args)
end

function M.complete(arg_lead)
  local choices = { 'current', 'local', 'mbp' }
  return vim.tbl_filter(function(value)
    return vim.startswith(value, arg_lead)
  end, choices)
end

function M.inspect(thread_id, host)
  if type(thread_id) ~= 'string' or thread_id == '' then
    notify('A Codex thread id is required', vim.log.levels.WARN)
    return
  end
  open_thread(host or 'local', thread_id)
end

function M.setup()
  if setup_done then
    return
  end
  setup_done = true
  patch_codecompanion_acp_tools()

  api.nvim_create_autocmd('VimLeavePre', {
    group = api.nvim_create_augroup('LpkeCodexSubagents', { clear = true }),
    callback = function()
      for _, state in pairs(dashboards) do
        stop_timer(state)
      end
      for _, state in pairs(thread_views) do
        stop_timer(state)
      end
      client_module.stop_all()
    end,
  })
end

return M
