local M = {}

local api = vim.api
local client_module = require('lpke.plugins.ai.helpers.codex_threads.client')
local formatter = require('lpke.plugins.ai.helpers.codex_threads.format')
local helpers = require('lpke.core.helpers')
local hints = require('lpke.plugins.ai.helpers.ui_hints')

local DASHBOARD_POLL_MS = 1500
local DASHBOARD_READ_CONCURRENCY = 6
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

local function show_buffer(bufnr, target_win)
  local winid = find_window(bufnr)
  if winid then
    api.nvim_set_current_win(winid)
    return winid
  end

  if target_win and api.nvim_win_is_valid(target_win) then
    api.nvim_set_current_win(target_win)
  else
    vim.cmd('botright vsplit')
  end
  winid = api.nvim_get_current_win()
  api.nvim_win_set_buf(winid, bufnr)
  if not target_win then
    vim.cmd('vertical resize 72')
  end
  vim.wo[winid].wrap = true
  vim.wo[winid].linebreak = true
  vim.wo[winid].conceallevel = 2
  return winid
end

local function replace_lines(bufnr, lines, hint_rows)
  if not valid_buffer(bufnr) then
    return
  end

  local buffer_lines = {}
  for _, line in ipairs(lines) do
    for _, part in ipairs(vim.split(tostring(line), '\n', { plain = true })) do
      table.insert(buffer_lines, (part:gsub('\r$', '')))
    end
  end

  if
    vim.deep_equal(api.nvim_buf_get_lines(bufnr, 0, -1, false), buffer_lines)
  then
    return
  end

  local winid = find_window(bufnr)
  local cursor = winid and api.nvim_win_get_cursor(winid) or nil
  local view = winid and api.nvim_win_call(winid, vim.fn.winsaveview)
  local old_count = api.nvim_buf_line_count(bufnr)
  local was_at_end = cursor and cursor[1] >= old_count

  vim.bo[bufnr].modifiable = true
  api.nvim_buf_set_lines(bufnr, 0, -1, false, buffer_lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
  hints.apply(bufnr, hint_rows)

  if not (winid and cursor) then
    return
  end

  local new_count = api.nvim_buf_line_count(bufnr)
  local row = was_at_end and new_count or math.min(cursor[1], new_count)
  view.lnum = math.max(1, row)
  api.nvim_win_call(winid, function()
    vim.fn.winrestview(view)
  end)
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
      if find_window(state.bufnr) then
        refresh(state)
      end
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

local function list_threads(state, callback, cursor, collected)
  local scope = state.scope
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
      if not valid_buffer(state.bufnr) then
        return
      end
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
        list_threads(state, callback, result.nextCursor, collected)
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

local function close_dashboard(state)
  for _, view in pairs(thread_views) do
    if view.dashboard == state and valid_buffer(view.bufnr) then
      api.nvim_buf_delete(view.bufnr, { force = true })
    end
  end
  if valid_buffer(state.bufnr) then
    api.nvim_buf_delete(state.bufnr, { force = true })
  end
end

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

local function toggle_completed_runs(state)
  local show_all = not vim.tbl_isempty(state.hidden_completions)
  local hidden = 0
  if show_all then
    for thread_id in pairs(state.hidden_completions) do
      state.hidden_completions[thread_id] = nil
    end
  else
    for _, summary in ipairs(state.threads) do
      local marker =
        formatter.completion_marker(dashboard_thread(state, summary))
      if marker then
        state.hidden_completions[summary.id] = marker
        hidden = hidden + 1
      end
    end
  end
  render_dashboard(state)
  notify(
    show_all and 'Showing all runs'
      or hidden > 0 and ('Hid ' .. hidden .. ' completed run(s)')
      or 'No completed runs to hide'
  )
end

local function set_dashboard_keymaps(state)
  local function move_agent(direction)
    local row = api.nvim_win_get_cursor(0)[1]
    local count = api.nvim_buf_line_count(state.bufnr)
    local remaining = vim.v.count1
    for candidate = row + direction, direction == 1 and count or 1, direction do
      local thread = state.line_threads[candidate]
      local previous = state.line_threads[candidate - 1]
      if thread and (not previous or thread.id ~= previous.id) then
        api.nvim_win_set_cursor(0, { candidate, 0 })
        remaining = remaining - 1
        if remaining == 0 then
          return
        end
      end
    end
  end
  helpers.keymap_set_multi({
    {
      'n!',
      'J',
      function()
        move_agent(1)
      end,
      { buffer = state.bufnr, desc = 'Codex subagents: Next agent' },
    },
    {
      'n!',
      'K',
      function()
        move_agent(-1)
      end,
      { buffer = state.bufnr, desc = 'Codex subagents: Previous agent' },
    },
    {
      'n!',
      '<Esc>',
      function()
        close_dashboard(state)
      end,
      { buffer = state.bufnr, desc = 'Codex subagents: Close' },
    },
  })
  helpers.keymap_set({
    'n!',
    'gA',
    function()
      close_dashboard(state)
    end,
    { buffer = state.bufnr, desc = 'Codex subagents: Close' },
  })
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
            state.execution_errors[thread.id],
            state
          )
        end
      end,
      { buffer = state.bufnr, desc = 'Codex subagents: Inspect thread' },
    },
    {
      'n!',
      'h',
      function()
        toggle_completed_runs(state)
      end,
      { buffer = state.bufnr, desc = 'Codex subagents: Toggle completed runs' },
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
        close_dashboard(state)
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
  local details = {}
  for _, summary in ipairs(threads) do
    details[summary.id] = dashboard_thread(state, summary)
  end
  local lines, line_threads, hint_rows = formatter.dashboard(
    state.scope,
    threads,
    details,
    state.parents,
    state.detail_errors,
    live_prompts,
    hidden_count
  )
  state.line_threads = line_threads
  replace_lines(state.bufnr, lines, hint_rows)
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

  for _, thread in ipairs(state.threads) do
    local marker = formatter.completion_marker(dashboard_thread(state, thread))
    local is_hidden = marker and marker == state.hidden_completions[thread.id]
    if not is_hidden then
      local version = detail_version(thread)
      local refresh_child = force
        or formatter.is_active(dashboard_thread(state, thread))
        or not state.details[thread.id]
        or state.detail_versions[thread.id] ~= version
      if refresh_child then
        add_task('child', thread.id, version)
      end

      local parent_id = formatter.parent_thread_id(thread)
      if parent_id and (force or not state.parents[parent_id]) then
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
    if not valid_buffer(state.bufnr) then
      return
    end
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
    end

    schedule_dashboard_render(state)
    if remaining == 0 then
      callback()
      return
    end
    launch()
  end

  launch = function()
    while
      valid_buffer(state.bufnr)
      and active < DASHBOARD_READ_CONCURRENCY
      and next_index <= #tasks
    do
      local task = tasks[next_index]
      next_index = next_index + 1
      active = active + 1
      local client = client_module.get(state.scope.host)
      local method = 'thread/read'
      local params = {
        threadId = task.id,
        includeTurns = true,
      }
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

  list_threads(state, function(threads, err)
    if not valid_buffer(state.bufnr) then
      return
    end
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
    execution_errors = {},
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
  vim.bo[state.bufnr].bufhidden = 'hide'
  vim.b[state.bufnr].codex_subagent_dashboard = true
  set_dashboard_keymaps(state)
  api.nvim_create_autocmd('BufWipeout', {
    buffer = state.bufnr,
    once = true,
    callback = function()
      stop_timer(state)
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
    if not valid_buffer(state.bufnr) then
      return
    end
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
    state.prompt = formatter.delegated_prompt(
      result.thread,
      state.dashboard
        and state.dashboard.parents[formatter.parent_thread_id(result.thread)],
      live_prompts[state.thread_id]
    ) or state.prompt
    local ok, encoded = pcall(vim.json.encode, { result.thread, state.prompt })
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
        state.execution_error,
        state.prompt
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
    if state.dashboard then
      state.dashboard.executions[state.thread_id] = state.execution
      state.dashboard.execution_errors[state.thread_id] = state.execution_error
    end
    if valid_buffer(state.bufnr) and state.thread then
      replace_lines(
        state.bufnr,
        formatter.thread(
          state.host,
          state.thread,
          state.execution,
          state.execution_error,
          state.prompt
        )
      )
    end
  end)
end

local function set_thread_keymaps(state)
  local function back()
    local win = find_window(state.bufnr)
    if state.dashboard and valid_buffer(state.dashboard.bufnr) then
      show_buffer(state.dashboard.bufnr, win)
    end
    if valid_buffer(state.bufnr) then
      api.nvim_buf_delete(state.bufnr, { force = true })
    end
  end
  helpers.keymap_set({
    'n!',
    '<Esc>',
    back,
    { buffer = state.bufnr, desc = 'Codex subagent: Back' },
  })
  helpers.keymap_set({
    'n!',
    'gA',
    function()
      if state.dashboard then
        close_dashboard(state.dashboard)
      else
        back()
      end
    end,
    { buffer = state.bufnr, desc = 'Codex subagent: Close panel' },
  })
  helpers.keymap_set_multi({
    {
      'n!',
      'r',
      function()
        refresh_thread_execution(state)
        refresh_thread(state)
      end,
      { buffer = state.bufnr, desc = 'Codex subagent: Refresh' },
    },
    {
      'n!',
      's',
      back,
      { buffer = state.bufnr, desc = 'Codex subagent: Dashboard' },
    },
    {
      'n!',
      'q',
      back,
      { buffer = state.bufnr, desc = 'Codex subagent: Back' },
    },
  })
end

open_thread = function(
  host,
  thread_id,
  summary,
  execution,
  execution_error,
  dashboard
)
  local key = thread_key(host, thread_id)
  local state = thread_views[key]
  if state and valid_buffer(state.bufnr) then
    state.dashboard = dashboard or state.dashboard
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
    dashboard = dashboard,
    prompt = summary and formatter.delegated_prompt(
      summary,
      dashboard and dashboard.parents[formatter.parent_thread_id(summary)],
      live_prompts[thread_id]
    ),
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
    }, execution, execution_error, state.prompt)
  )
  show_buffer(state.bufnr, dashboard and find_window(dashboard.bufnr))
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

function M.toggle()
  local parent_id = current_parent_id()
  if not parent_id then
    notify('No active Codex ACP chat with a session id', vim.log.levels.WARN)
    return
  end
  local scope =
    { label = 'Current chat', host = 'local', parent_id = parent_id }
  local state = dashboards[scope_key(scope)]
  if state then
    local visible = find_window(state.bufnr)
    for _, view in pairs(thread_views) do
      visible = visible or (view.dashboard == state and find_window(view.bufnr))
    end
    if visible then
      close_dashboard(state)
      return
    end
  end
  open_dashboard(scope)
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
