local M = {}

local ai_config = require('lpke.plugins.ai.helpers.config')
local lifecycle = require('lpke.plugins.ai.helpers.acp_lifecycle')

local function has_sent_user_message(chat)
  return vim.iter(chat.messages or {}):any(function(msg)
    return msg.role == 'user' and msg._meta and msg._meta.sent
  end)
end

local function is_fresh_acp_chat(chat)
  return chat
    and chat.adapter
    and chat.adapter.type == 'acp'
    and (chat.cycle or 1) <= 1
    and not has_sent_user_message(chat)
end

local function open_codecompanion_history()
  vim.cmd('CodeCompanionHistory')
end

local function chat_title(chat)
  return (chat and chat.title)
    or (chat and chat.opts and chat.opts.title)
    or (chat and ('Chat ' .. chat.id))
    or 'Untitled'
end

local function local_utc_offset(timestamp)
  local local_time = os.time(os.date('*t', timestamp))
  local utc_as_local = os.time(os.date('!*t', timestamp))
  return os.difftime(local_time, utc_as_local)
end

local function parse_iso8601_utc(iso)
  local year, month, day, hour, min, sec, offset =
    iso:match('^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)%.?%d*([Zz]?)$')

  if not year then
    year, month, day, hour, min, sec, offset = iso:match(
      '^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)%.?%d*([%+%-]%d%d:?%d%d)$'
    )
  end

  if not year then
    return nil
  end

  local timestamp = os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
  })

  local source_offset = 0
  if offset and offset ~= '' and not offset:match('^[Zz]$') then
    local sign, off_hour, off_min = offset:match('^([%+%-])(%d%d):?(%d%d)$')
    source_offset = (tonumber(off_hour) * 3600) + (tonumber(off_min) * 60)
    if sign == '-' then
      source_offset = -source_offset
    end
  end

  return timestamp + local_utc_offset(timestamp) - source_offset
end

local function format_session(session)
  local parts = {}

  if session.updatedAt then
    local utils = require('codecompanion.utils')
    local ts = parse_iso8601_utc(session.updatedAt)
    if ts then
      table.insert(parts, '(' .. utils.make_relative(ts) .. ')')
    end
  end

  table.insert(parts, session.title or session.sessionId)
  return table.concat(parts, ' ')
end

local function open_chats(current_chat)
  local ok, codecompanion = pcall(require, 'codecompanion')
  if not ok or type(codecompanion.buf_get_chat) ~= 'function' then
    return {}
  end

  local entries = {}
  for _, item in ipairs(codecompanion.buf_get_chat() or {}) do
    local chat = item.chat
    if
      chat
      and chat ~= current_chat
      and chat.adapter
      and chat.adapter.type == 'acp'
    then
      local session_id = lifecycle.get_session_id(chat)
      table.insert(entries, {
        display = '[open] ' .. chat_title(chat),
        kind = 'open',
        chat = chat,
        session_id = session_id,
      })
    end
  end

  table.sort(entries, function(a, b)
    return a.display < b.display
  end)

  return entries
end

local function close_disposable_resume_chat(chat)
  if is_fresh_acp_chat(chat) then
    lifecycle.close_disposable_chat(chat)
  end
end

local function open_existing_chat(current_chat, target_chat)
  if not target_chat then
    return
  end

  if current_chat and current_chat ~= target_chat and current_chat.ui then
    pcall(function()
      current_chat.ui:hide()
    end)
  end

  pcall(function()
    target_chat.ui:open()
  end)

  lifecycle.ensure_chat_connection(target_chat, nil, {
    keep_visible = true,
  })
  vim.notify('Open chat resumed', vim.log.levels.INFO, {
    title = 'CodeCompanion',
  })

  if current_chat and current_chat ~= target_chat then
    close_disposable_resume_chat(current_chat)
  end
end

local function load_acp_session(chat, selected)
  local updates = {}
  local ok = chat.acp_connection:load_session(selected.sessionId, {
    on_session_update = function(update)
      table.insert(updates, update)
    end,
  })

  if not ok then
    return vim.notify('Failed to load session', vim.log.levels.ERROR, {
      title = 'CodeCompanion',
    })
  end

  require('codecompanion.interactions.chat.acp.commands').link_buffer_to_session(
    chat.bufnr,
    chat.acp_connection.session_id
  )

  require('codecompanion.interactions.chat.acp.render').restore_session(
    chat,
    updates
  )

  if selected.title then
    chat:set_title(selected.title)
  end

  lifecycle.remember_session(chat)

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'CodeCompanionACPChatRestored',
    data = {
      bufnr = chat.bufnr,
      id = chat.id,
      session_id = chat.acp_connection.session_id,
      title = chat.title,
    },
  })

  vim.notify('ACP session resumed', vim.log.levels.INFO, {
    title = 'CodeCompanion',
  })
end

local function acp_sessions(chat, open_entries)
  local seen = {}
  for _, entry in ipairs(open_entries) do
    if entry.session_id then
      seen[entry.session_id] = true
    end
  end

  if
    not chat.acp_connection
    or not chat.acp_connection:can_list_sessions()
    or not chat.acp_connection:can_load_session()
  then
    return {}
  end

  local sessions = chat.acp_connection:session_list({
    max_sessions = 500,
  })

  local entries = {}
  for _, session in ipairs(sessions or {}) do
    if session.sessionId and not seen[session.sessionId] then
      table.insert(entries, {
        display = '[saved] ' .. format_session(session),
        kind = 'saved',
        session = session,
        session_id = session.sessionId,
      })
    end
  end

  return entries
end

local function pick_acp_session(chat)
  local open_entries = open_chats(chat)
  local entries =
    vim.list_extend(open_entries, acp_sessions(chat, open_entries))

  if #entries == 0 then
    return vim.notify('No previous ACP sessions found', vim.log.levels.INFO, {
      title = 'CodeCompanion',
    })
  end

  vim.ui.select(entries, {
    prompt = 'ACP Resume',
    kind = 'codecompanion.nvim',
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if not choice then
      return
    end

    if choice.kind == 'open' then
      return open_existing_chat(chat, choice.chat)
    end

    load_acp_session(chat, choice.session)
  end)
end

local function run_resume(chat)
  local function execute_resume()
    pick_acp_session(chat)
  end

  if chat.acp_connection and chat.acp_connection:is_ready() then
    execute_resume()
    return
  end

  require('codecompanion.interactions.chat.helpers').create_acp_connection(
    chat,
    execute_resume
  )
end

local function open_acp_resume_chat(source_chat, cb)
  if source_chat and source_chat.ui then
    pcall(function()
      source_chat.ui:hide()
    end)
  end

  vim.g.lpke_cc_chat_create_notified = true
  vim.cmd('CodeCompanionChat')
  vim.notify('ACP resume chat opened', vim.log.levels.INFO, {
    title = 'CodeCompanion',
  })

  local chat = require('codecompanion.interactions.chat').buf_get_chat(0)
  if not chat then
    return
  end

  local adapter = ai_config.defaults.chat_adapter
  if chat.adapter and chat.adapter.type == 'acp' then
    cb(chat)
    return
  end

  chat:change_adapter(adapter, function()
    require('lpke.plugins.ai.helpers.chat_functions').remove_http_tool_context(
      chat.bufnr
    )
    cb(chat)
  end)
end

local choices = {
  {
    display = 'ACP resume',
    value = 'resume',
  },
  {
    display = 'CodeCompanion history',
    value = 'history',
  },
}

local function handle_choice(chat, choice)
  if not choice then
    return
  end

  local value = type(choice) == 'table' and choice.value or choice
  if value == 'resume' then
    if not (chat and chat.adapter and chat.adapter.type == 'acp') then
      return open_acp_resume_chat(chat, run_resume)
    end
    run_resume(chat)
  elseif value == 'history' then
    open_codecompanion_history()
  end
end

local function pick_history_action(chat)
  vim.ui.select(choices, {
    prompt = 'Chat History',
    kind = 'codecompanion.nvim',
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    handle_choice(chat, choice)
  end)
end

function M.open(chat)
  pick_history_action(chat)
end

return M
