local M = {}

local function value_or_nil(value)
  return value ~= vim.NIL and value or nil
end

local function list(value)
  return type(value) == 'table' and value or {}
end

local function text(value)
  return type(value) == 'string' and value or nil
end

local function single_line(value)
  local normalized = text(value)
  if not normalized then
    return nil
  end

  normalized = vim.trim(normalized:gsub('%s+', ' '))
  return normalized ~= '' and normalized or nil
end

local function first_value(...)
  for index = 1, select('#', ...) do
    local value = value_or_nil(select(index, ...))
    if value ~= nil then
      return value
    end
  end
end

local function append(lines, value)
  value = value_or_nil(value)
  if value == nil then
    return
  end

  for _, line in ipairs(vim.split(tostring(value), '\n', { plain = true })) do
    table.insert(lines, line)
  end
end

local function append_section(lines, heading, value)
  value = value_or_nil(value)
  if value == nil or value == '' then
    return
  end

  table.insert(lines, '### ' .. heading)
  table.insert(lines, '')
  append(lines, value)
  table.insert(lines, '')
end

local function inspect(value)
  if value == nil or value == vim.NIL then
    return nil
  end
  if type(value) == 'string' then
    return value
  end
  return vim.inspect(value)
end

local function join_text(value)
  value = value_or_nil(value)
  if type(value) == 'string' then
    return value
  end
  if type(value) ~= 'table' then
    return inspect(value)
  end

  local parts = {}
  for _, item in ipairs(value) do
    if type(item) == 'string' then
      table.insert(parts, item)
    elseif type(item) == 'table' then
      if type(item.text) == 'string' then
        table.insert(parts, item.text)
      elseif item.type == 'image' or item.type == 'localImage' then
        table.insert(
          parts,
          '[image: ' .. tostring(first_value(item.path, item.url) or '') .. ']'
        )
      else
        table.insert(parts, inspect(item))
      end
    end
  end
  return table.concat(parts, '\n\n')
end

local function status_name(status)
  status = value_or_nil(status)
  if type(status) == 'table' then
    return text(status.type) or text(status.status) or 'unknown'
  end
  return text(status) or 'unknown'
end

local function duration(value)
  if type(value) ~= 'number' then
    return nil
  end
  if value < 1000 then
    return value .. 'ms'
  end
  return string.format('%.1fs', value / 1000)
end

local function fenced(value, language)
  value = value_or_nil(value)
  if value == nil or value == '' then
    return nil
  end
  return table.concat({
    '````' .. (language or ''),
    tostring(value),
    '````',
  }, '\n')
end

local function item_title(item)
  local status = status_name(item.status)
  if item.type == 'commandExecution' then
    return 'Command · ' .. status
  elseif item.type == 'fileChange' then
    return 'File changes · ' .. status
  elseif item.type == 'mcpToolCall' then
    return table.concat(
      { 'MCP', text(item.server) or '?', text(item.tool) or '?', status },
      ' · '
    )
  elseif item.type == 'dynamicToolCall' then
    return table.concat({ 'Tool', text(item.tool) or '?', status }, ' · ')
  elseif item.type == 'collabAgentToolCall' then
    return table.concat({ 'Subagent', text(item.tool) or '?', status }, ' · ')
  elseif item.type == 'webSearch' then
    return 'Web search'
  elseif item.type == 'imageGeneration' then
    return 'Image generation · ' .. status
  end
  return item.type or 'Item'
end

local function format_changes(changes)
  local lines = {}
  for _, change in ipairs(list(changes)) do
    local path = text(change.path)
      or text(change.file)
      or text(change.filePath)
      or '?'
    local kind = text(change.kind) or text(change.type) or 'change'
    table.insert(lines, '- `' .. tostring(path) .. '` · ' .. tostring(kind))
  end
  return table.concat(lines, '\n')
end

local function format_item(lines, item)
  if item.type == 'userMessage' then
    append_section(lines, 'User', join_text(item.content))
  elseif item.type == 'hookPrompt' then
    append_section(lines, 'Hook prompt', join_text(item.fragments))
  elseif item.type == 'agentMessage' then
    local phase = text(item.phase) and (' · ' .. item.phase) or ''
    append_section(lines, 'Agent' .. phase, item.text)
  elseif item.type == 'reasoning' then
    local text = join_text(item.summary)
    if not text or text == '' then
      text = join_text(item.content)
    end
    append_section(lines, 'Reasoning', text)
  elseif item.type == 'plan' then
    append_section(lines, 'Plan', item.text)
  elseif item.type == 'commandExecution' then
    local command = type(item.command) == 'table'
        and table.concat(item.command, ' ')
      or item.command
    local details = {}
    if text(item.cwd) then
      table.insert(details, 'cwd: `' .. item.cwd .. '`')
    end
    if item.exitCode ~= nil and item.exitCode ~= vim.NIL then
      table.insert(details, 'exit: `' .. tostring(item.exitCode) .. '`')
    end
    if duration(item.durationMs) then
      table.insert(details, 'duration: `' .. duration(item.durationMs) .. '`')
    end
    append_section(
      lines,
      item_title(item),
      table.concat({
        fenced(command, 'sh') or '',
        table.concat(details, ' · '),
        fenced(item.aggregatedOutput, 'text') or '',
      }, '\n\n')
    )
  elseif item.type == 'fileChange' then
    append_section(lines, item_title(item), format_changes(item.changes))
  elseif item.type == 'mcpToolCall' then
    append_section(
      lines,
      item_title(item),
      table.concat({
        fenced(inspect(item.arguments), 'lua') or '',
        fenced(inspect(first_value(item.result, item.error)), 'lua') or '',
      }, '\n\n')
    )
  elseif item.type == 'dynamicToolCall' then
    append_section(
      lines,
      item_title(item),
      table.concat({
        fenced(inspect(item.arguments), 'lua') or '',
        fenced(inspect(item.contentItems), 'lua') or '',
      }, '\n\n')
    )
  elseif item.type == 'collabAgentToolCall' then
    local children = {}
    for _, id in ipairs(list(item.receiverThreadIds)) do
      table.insert(children, '- `' .. id .. '`')
    end
    append_section(
      lines,
      item_title(item),
      table.concat({
        text(item.prompt) or '',
        #children > 0 and ('Children:\n' .. table.concat(children, '\n')) or '',
        inspect(item.agentsStates) or '',
      }, '\n\n')
    )
  elseif item.type == 'subAgentActivity' then
    append_section(
      lines,
      'Subagent activity',
      table.concat({
        'Thread: `' .. (text(item.agentThreadId) or '?') .. '`',
        'Kind: `' .. (text(item.kind) or '?') .. '`',
        text(item.agentPath) and ('Path: `' .. item.agentPath .. '`') or '',
      }, '\n')
    )
  elseif item.type == 'webSearch' then
    append_section(
      lines,
      item_title(item),
      text(item.query) or inspect(item.action) or inspect(item.results)
    )
  elseif item.type == 'imageView' then
    append_section(
      lines,
      'Viewed image',
      '`' .. (text(item.path) or '?') .. '`'
    )
  elseif item.type == 'imageGeneration' then
    append_section(
      lines,
      item_title(item),
      inspect(first_value(item.result, item.failure, item.revisedPrompt))
    )
  elseif item.type == 'enteredReviewMode' then
    append_section(lines, 'Entered review mode', item.review)
  elseif item.type == 'exitedReviewMode' then
    append_section(lines, 'Review', item.review)
  elseif item.type == 'contextCompaction' then
    append_section(lines, 'Context', 'Compacted')
  elseif item.type == 'sleep' then
    append_section(lines, 'Sleep', duration(item.durationMs) or 'Waiting')
  else
    append_section(lines, item_title(item), inspect(item))
  end
end

function M.thread_status(thread)
  local turns = list(thread.turns)
  local last_turn = turns[#turns]
  if last_turn and last_turn.status then
    return status_name(last_turn.status)
  end
  return status_name(thread.status)
end

local terminal_statuses = {
  canceled = true,
  cancelled = true,
  closed = true,
  completed = true,
  failed = true,
  interrupted = true,
  shutdown = true,
}

function M.completion_marker(thread)
  local status = M.thread_status(thread)
  local normalized = status:lower():gsub('[%s_-]', '')
  if not terminal_statuses[normalized] then
    return nil
  end

  local turns = list(thread.turns)
  local last_turn = turns[#turns] or {}
  local revision = first_value(
    thread.updatedAt,
    thread.recencyAt,
    last_turn.completedAt,
    last_turn.id,
    thread.createdAt
  )
  return table.concat(
    { tostring(thread.id or ''), normalized, tostring(revision or '') },
    ':'
  )
end

local function spawn_source(thread)
  local source = type(thread.source) == 'table' and thread.source or {}
  local subagent = type(source.subAgent) == 'table' and source.subAgent
    or type(source.subagent) == 'table' and source.subagent
    or {}
  return type(subagent.thread_spawn) == 'table' and subagent.thread_spawn
    or type(subagent.threadSpawn) == 'table' and subagent.threadSpawn
    or {}
end

local function execution_value(execution, ...)
  execution = type(execution) == 'table' and execution or {}
  for index = 1, select('#', ...) do
    local value = value_or_nil(execution[select(index, ...)])
    if value ~= nil then
      return value
    end
  end
end

local function simple_value(value)
  value = value_or_nil(value)
  if type(value) == 'table' then
    return single_line(value.type)
      or single_line(value.name)
      or single_line(value.mode)
  end
  if type(value) == 'number' or type(value) == 'boolean' then
    return tostring(value)
  end
  return single_line(value)
end

local function execution_details(thread, execution)
  local spawn = spawn_source(thread)
  local fields = {
    { 'Model', execution_value(execution, 'model') },
    {
      'Reasoning effort',
      execution_value(
        execution,
        'reasoningEffort',
        'reasoning_effort',
        'effort'
      ),
    },
    { 'Service tier', execution_value(execution, 'serviceTier') },
    {
      'Provider',
      execution_value(execution, 'modelProvider') or thread.modelProvider,
    },
    { 'Approval policy', execution_value(execution, 'approvalPolicy') },
    {
      'Permission profile',
      execution_value(execution, 'activePermissionProfile'),
    },
    { 'Sandbox', execution_value(execution, 'sandbox') },
    { 'Multi-agent mode', execution_value(execution, 'multiAgentMode') },
    { 'Working directory', execution_value(execution, 'cwd') or thread.cwd },
    { 'Agent path', first_value(spawn.agent_path, spawn.agentPath) },
    { 'Spawn depth', spawn.depth },
    { 'Codex CLI', thread.cliVersion },
  }
  local lines = {}
  for _, field in ipairs(fields) do
    local value = simple_value(field[2])
    if value then
      table.insert(lines, field[1] .. ': `' .. value .. '`')
    end
  end
  return lines
end

local function append_execution_section(lines, thread, execution, error)
  local details = execution_details(thread, execution)
  if #details > 0 and execution then
    append_section(lines, 'Execution settings', table.concat(details, '\n'))
  elseif error then
    append_section(
      lines,
      'Execution settings',
      '_Unavailable: ' .. error .. '_'
    )
  else
    append_section(lines, 'Execution settings', '_Loading..._')
  end
end

function M.parent_thread_id(thread)
  local spawn = spawn_source(thread)
  return text(thread.parentThreadId)
    or text(spawn.parent_thread_id)
    or text(spawn.parentThreadId)
end

local function receiver_matches(item, thread_id)
  for _, receiver_id in ipairs(list(item.receiverThreadIds)) do
    if receiver_id == thread_id then
      return true
    end
  end
  return false
end

function M.delegated_prompt(thread, parent, live_prompt)
  if type(live_prompt) == 'string' and live_prompt ~= '' then
    return live_prompt
  end

  local spawn = spawn_source(thread)
  for _, prompt in ipairs({
    thread.delegationPrompt,
    spawn.prompt,
    spawn.message,
    spawn.task,
  }) do
    if
      type(prompt) == 'string'
      and prompt ~= ''
      and not prompt:match('^gAAAAA[%w_-]+$')
    then
      return prompt
    end
  end

  for _, turn in ipairs(list(parent and parent.turns)) do
    for _, item in ipairs(list(turn.items)) do
      if
        item.type == 'collabAgentToolCall'
        and receiver_matches(item, thread.id)
        and type(item.prompt) == 'string'
        and item.prompt ~= ''
      then
        return item.prompt
      end
    end
  end
end

local function response_turns(thread)
  local turns = list(thread.turns)
  local created_at = thread.createdAt
  local matching = {}
  local has_started_at = false

  if type(created_at) == 'number' then
    for _, turn in ipairs(turns) do
      if type(turn.startedAt) == 'number' then
        has_started_at = true
        if turn.startedAt >= created_at then
          table.insert(matching, turn)
        end
      end
    end
  end

  if #matching == 0 and not has_started_at and #turns > 0 then
    table.insert(matching, turns[#turns])
  end
  return matching
end

function M.subagent_messages(thread)
  local messages = {}
  for _, turn in ipairs(response_turns(thread)) do
    for _, item in ipairs(list(turn.items)) do
      if item.type == 'agentMessage' and type(item.text) == 'string' then
        table.insert(messages, {
          phase = text(item.phase),
          text = item.text,
        })
      end
    end
  end
  return messages
end

function M.thread_label(thread)
  local name = single_line(thread.agentNickname) or single_line(thread.name)
  local role = single_line(thread.agentRole)

  local parts = { '[' .. M.thread_status(thread) .. ']' }
  if name and name ~= '' then
    table.insert(parts, name)
  end
  if role and role ~= '' then
    table.insert(parts, '(' .. role .. ')')
  end
  table.insert(parts, '[' .. tostring(thread.id or '?') .. ']')
  return table.concat(parts, ' ')
end

local function append_subagent_entry(
  lines,
  thread,
  parent,
  live_prompt,
  load_error,
  execution,
  execution_error
)
  table.insert(lines, '## ' .. M.thread_label(thread))
  table.insert(lines, '')

  append_execution_section(lines, thread, execution, execution_error)

  if load_error then
    append_section(lines, 'Read error', load_error)
    return
  end

  if not thread.turns then
    table.insert(lines, '_Loading full thread..._')
    table.insert(lines, '')
    return
  end

  append_section(
    lines,
    'Delegated prompt',
    M.delegated_prompt(thread, parent, live_prompt)
      or '_Unavailable. Codex did not expose the encrypted spawn prompt._'
  )

  local messages = M.subagent_messages(thread)
  if #messages == 0 then
    append_section(lines, 'Subagent response', '_Waiting for output..._')
    return
  end

  for _, message in ipairs(messages) do
    local phase = message.phase and (' · ' .. message.phase) or ''
    append_section(lines, 'Subagent response' .. phase, message.text)
  end
end

function M.dashboard(
  scope,
  threads,
  details,
  parents,
  detail_errors,
  live_prompts,
  executions,
  execution_errors,
  hidden_count
)
  local lines = {
    '# Codex subagents',
    '',
    'Source: `' .. scope.label .. '`',
    'Updated: `' .. os.date('%Y-%m-%d %H:%M:%S') .. '`',
    '',
    '`<CR>` full transcript · `h` hide completed so far · `u` show all',
    '`r` refresh · `s` change source · `q` close',
    '',
  }
  local line_threads = {}

  hidden_count = hidden_count or 0
  if hidden_count > 0 then
    table.insert(lines, 5, 'Hidden: `' .. hidden_count .. '` completed run(s)')
  end

  if #threads == 0 then
    if hidden_count > 0 then
      table.insert(lines, 'No visible subagent threads.')
    else
      table.insert(lines, 'No subagent threads found.')
    end
    return lines, line_threads
  end

  details = details or {}
  parents = parents or {}
  detail_errors = detail_errors or {}
  live_prompts = live_prompts or {}
  executions = executions or {}
  execution_errors = execution_errors or {}
  for _, summary in ipairs(threads) do
    local first_line = #lines + 1
    local thread = details[summary.id] or summary
    local parent = parents[M.parent_thread_id(thread)]
    append_subagent_entry(
      lines,
      thread,
      parent,
      live_prompts[summary.id],
      detail_errors[summary.id],
      executions[summary.id],
      execution_errors[summary.id]
    )
    table.insert(lines, '---')
    table.insert(lines, '')
    for line = first_line, #lines do
      line_threads[line] = thread
    end
  end

  return lines, line_threads
end

function M.thread(host, thread, execution, execution_error)
  local lines = {
    '# Codex subagent',
    '',
    'Host: `' .. host .. '`',
    'Status: `' .. M.thread_status(thread) .. '`',
    'Thread: `' .. tostring(thread.id or '?') .. '`',
  }

  if text(thread.parentThreadId) then
    table.insert(lines, 'Parent: `' .. thread.parentThreadId .. '`')
  end
  if text(thread.agentNickname) then
    table.insert(lines, 'Agent: `' .. thread.agentNickname .. '`')
  end
  if text(thread.agentRole) then
    table.insert(lines, 'Role: `' .. thread.agentRole .. '`')
  end

  for _, line in ipairs(execution_details(thread, execution)) do
    table.insert(lines, line)
  end
  if not execution then
    table.insert(
      lines,
      execution_error
          and ('Execution settings: unavailable: ' .. execution_error)
        or 'Execution settings: loading...'
    )
  end

  table.insert(lines, '')
  table.insert(lines, '`r` refresh · `s` subagent dashboard · `q` close')
  table.insert(lines, '')
  table.insert(lines, '---')
  table.insert(lines, '')

  for index, turn in ipairs(list(thread.turns)) do
    local turn_details = { status_name(turn.status) }
    if duration(turn.durationMs) then
      table.insert(turn_details, duration(turn.durationMs))
    end
    table.insert(
      lines,
      '## Turn ' .. index .. ' · ' .. table.concat(turn_details, ' · ')
    )
    table.insert(lines, '')

    for _, item in ipairs(list(turn.items)) do
      format_item(lines, item)
    end

    if turn.error and turn.error ~= vim.NIL then
      append_section(lines, 'Turn error', inspect(turn.error))
    end
  end

  return lines
end

return M
