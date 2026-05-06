local M = {}

local chat_fns = require('lpke.plugins.ai.helpers.chat_functions')
local lifecycle = require('lpke.plugins.ai.helpers.acp_lifecycle')

local function current_chat()
  local ok, chat_module = pcall(require, 'codecompanion.interactions.chat')
  if not ok or type(chat_module.buf_get_chat) ~= 'function' then
    return nil
  end
  return chat_module.buf_get_chat(0)
end

local function open_chats()
  local ok, codecompanion = pcall(require, 'codecompanion')
  if not ok or type(codecompanion.buf_get_chat) ~= 'function' then
    return {}
  end

  local chats = {}
  for _, item in ipairs(codecompanion.buf_get_chat() or {}) do
    if item.chat then
      table.insert(chats, item.chat)
    end
  end
  return chats
end

local function is_acp_chat(chat)
  return chat and chat.adapter and chat.adapter.type == 'acp'
end

local function build_choices(chat)
  local choices = {
    {
      display = 'Cancel',
      value = 'cancel',
    },
    {
      display = 'Close empty CodeCompanion chats',
      value = 'close_empty_chats',
    },
  }

  if is_acp_chat(chat) then
    vim.list_extend(choices, {
      {
        display = 'Suspend all ACP chats (except this one)',
        value = 'suspend_other_acp',
      },
      {
        display = 'Suspend all ACP chats (including this one)',
        value = 'suspend_all_acp',
      },
    })
  else
    vim.list_extend(choices, {
      {
        display = 'Suspend all ACP chats',
        value = 'suspend_all_acp',
      },
    })
  end

  return choices
end

local function notify_suspend_result(result)
  if result.suspended == 0 and result.killed_tracked_roots == 0 then
    vim.notify('No ACP chats to suspend', vim.log.levels.INFO, {
      title = 'CodeCompanion',
    })
    return
  end

  local msg = string.format(
    'Suspended %d ACP chat%s',
    result.suspended,
    result.suspended == 1 and '' or 's'
  )

  if result.killed_tracked_roots > result.suspended then
    msg = msg
      .. string.format(
        ' and killed %d tracked ACP process root%s',
        result.killed_tracked_roots,
        result.killed_tracked_roots == 1 and '' or 's'
      )
  end

  if result.already_disconnected > 0 then
    msg = msg
      .. string.format(
        ' (%d already disconnected)',
        result.already_disconnected
      )
  end

  if result.skipped_tracked_roots then
    msg = msg .. '; skipped tracked process sweep to preserve current ACP chat'
  end

  vim.notify(msg, vim.log.levels.INFO, { title = 'CodeCompanion' })
end

local function stop_current_request(chat)
  if not chat then
    vim.notify('No current CodeCompanion chat', vim.log.levels.INFO, {
      title = 'CodeCompanion',
    })
    return
  end

  if not chat.current_request and not chat.current_tool then
    vim.notify('No current request to stop', vim.log.levels.INFO, {
      title = 'CodeCompanion',
    })
    return
  end

  chat:stop()
  vim.notify('Stopped current request', vim.log.levels.INFO, {
    title = 'CodeCompanion',
  })
end

local function is_empty_chat(chat)
  if
    not chat
    or not chat.bufnr
    or not vim.api.nvim_buf_is_valid(chat.bufnr)
  then
    return false
  end

  if not vim.api.nvim_buf_is_loaded(chat.bufnr) then
    return false
  end

  if chat.current_request or chat.current_tool then
    return false
  end

  return chat_fns.is_empty_chat(chat.bufnr)
    or chat_fns.is_chat_only_http_tool_context(chat.bufnr)
end

function M.close_empty_chats(current)
  local closed = 0

  for _, chat in ipairs(open_chats()) do
    if chat ~= current and is_empty_chat(chat) then
      local ok = pcall(function()
        chat:close()
      end)
      if ok then
        closed = closed + 1
      end
    end
  end

  vim.notify(
    string.format(
      'Closed %d empty CodeCompanion chat%s',
      closed,
      closed == 1 and '' or 's'
    ),
    vim.log.levels.INFO,
    { title = 'CodeCompanion' }
  )

  return closed
end

local function handle_choice(chat, choice)
  if not choice or choice.value == 'cancel' then
    return
  end

  if choice.value == 'suspend_other_acp' then
    local result = lifecycle.suspend_other_acp_chats(chat, {
      stop_request = true,
      delay_ms = 100,
    })
    notify_suspend_result(result)
  elseif choice.value == 'suspend_all_acp' then
    local result = lifecycle.suspend_all_acp_chats(chat, {
      stop_request = true,
      delay_ms = 100,
    })
    notify_suspend_result(result)
  elseif choice.value == 'stop_current_request' then
    stop_current_request(chat)
  elseif choice.value == 'close_empty_chats' then
    M.close_empty_chats(chat)
  end
end

function M.open()
  local chat = current_chat()

  vim.ui.select(build_choices(chat), {
    prompt = 'CodeCompanion Cleanup',
    kind = 'codecompanion.nvim',
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    handle_choice(chat, choice)
  end)
end

return M
