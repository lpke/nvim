local M = {}

-- codex-acp handles this locally, so no empty Codex turn reaches the thread.
local fallback_prompt = '/status'

local function notify(message)
  vim.notify(message, vim.log.levels.WARN, { title = 'CodeCompanion' })
end

local function has_prompt(chat)
  local ok, message = pcall(
    require('codecompanion.interactions.chat.parser').messages,
    chat,
    chat.header_line
  )

  if not ok then
    return true
  end

  return message
    and type(message.content) == 'string'
    and vim.trim(message.content) ~= ''
end

local function is_codex_acp(chat)
  return chat.adapter
    and chat.adapter.type == 'acp'
    and chat.adapter.name == 'codex'
end

local function prevent_empty(chat)
  if has_prompt(chat) then
    return
  end

  notify('Prompt is empty')
  return false
end

function M.submit(chat)
  if prevent_empty(chat) == false then
    return
  end

  chat:submit()
end

function M.attach(chat)
  if not chat or chat._lpke_submit_guard then
    return
  end

  chat._lpke_submit_guard = true
  chat:add_callback('on_before_submit', function(current_chat)
    if not is_codex_acp(current_chat) then
      return
    end

    return prevent_empty(current_chat)
  end)
end

function M.setup()
  vim.api.nvim_create_autocmd('User', {
    pattern = 'CodeCompanionChatCreated',
    group = vim.api.nvim_create_augroup('LpkeCodeCompanionSubmitGuard', {
      clear = true,
    }),
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if not bufnr then
        return
      end

      M.attach(require('codecompanion').buf_get_chat(bufnr))
    end,
  })
end

function M.wrap_acp_form_messages(form_messages)
  return function(adapter, messages, capabilities)
    local prompt = form_messages(adapter, messages, capabilities)
    if type(prompt) == 'table' and not vim.tbl_isempty(prompt) then
      return prompt
    end

    notify('Empty ACP prompt replaced with /status')
    return { { type = 'text', text = fallback_prompt } }
  end
end

return M
