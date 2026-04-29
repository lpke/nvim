local M = {}

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

local function run_resume(chat)
  local function execute_resume()
    local config = require('codecompanion.config')
    local slash_commands =
      require('codecompanion.interactions.chat.slash_commands')

    slash_commands.new():execute({
      label = 'resume',
      config = config.interactions.chat.slash_commands.resume,
    }, chat)
  end

  if chat.acp_connection then
    execute_resume()
    return
  end

  require('codecompanion.interactions.chat.helpers').create_acp_connection(
    chat,
    execute_resume
  )
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
    run_resume(chat)
  elseif value == 'history' then
    open_codecompanion_history()
  end
end

local function pick_history_action(chat)
  vim.ui.select(choices, {
    prompt = 'Chat History',
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    handle_choice(chat, choice)
  end)
end

function M.open(chat)
  if is_fresh_acp_chat(chat) then
    pick_history_action(chat)
    return
  end

  open_codecompanion_history()
end

return M
