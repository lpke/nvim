local ai_config = require('lpke.plugins.ai.helpers.config')

local M = {}
local registry = require('lpke.plugins.ai.helpers.chat_registry')

function M.is_acp_adapter(adapter)
  return adapter and adapter.type == 'acp'
end

function M.is_codex_adapter(adapter)
  return M.is_acp_adapter(adapter) and adapter.name == 'codex'
end

function M.get_cur_model(bufnr)
  local chat = registry.get(bufnr)
  if not chat then
    return nil
  end
  local adapter = chat.adapter
  if not adapter then
    return nil
  end

  if M.is_acp_adapter(adapter) then
    if chat.acp_connection then
      local models = chat.acp_connection:get_models()
      if models and models.currentModelId then
        return models.currentModelId
      end
    end

    local defaults = adapter.defaults or {}
    local session_config_options = defaults.session_config_options or {}
    return session_config_options.model or defaults.model
  end

  local default = adapter.schema.model.default
  local resolved = chat.settings.model or (adapter.opts and adapter.opts.model)
  return type(resolved) == 'string' and resolved
    or type(default) == 'string' and default
    or nil
end

function M.get_cur_adapter(bufnr)
  local chat = registry.get(bufnr)
  return chat and chat.adapter and chat.adapter.name
end

function M.get_cur_acp_mode(bufnr)
  local chat = registry.get(bufnr)
  if not chat or not M.is_acp_adapter(chat.adapter) then
    return nil
  end

  if chat.acp_connection then
    for _, opt in ipairs(chat.acp_connection:get_config_options() or {}) do
      if opt.category == 'mode' then
        local current_value = opt.currentValue
        local values =
          require('codecompanion.acp').flatten_config_options(opt.options or {})
        for _, val in ipairs(values) do
          if val.value == current_value then
            return val.name or val.value
          end
        end
        return current_value
      end
    end
  end

  local defaults = chat.adapter.defaults or {}
  local session_config_options = defaults.session_config_options or {}
  return session_config_options.mode or defaults.mode
end

function M.is_codex_chat(bufnr)
  local chat = registry.get(bufnr)
  return chat and M.is_codex_adapter(chat.adapter)
end

local function current_chat(chat)
  chat = chat or registry.get()
  if not chat then
    vim.notify('Not in a CodeCompanion chat buffer', vim.log.levels.ERROR)
  end
  return chat
end

-- Resolve choice metadata only for an explicit model change, never rendering.
local function available_model_ids(chat)
  local choices
  if M.is_acp_adapter(chat.adapter) then
    local models = chat.acp_connection and chat.acp_connection:get_models()
    choices = models and models.availableModels
  else
    choices = chat.adapter.schema.model.choices
    if type(choices) == 'function' then
      local ok, value = pcall(choices, chat.adapter, { async = false })
      choices = ok and value or nil
    end
  end
  if type(choices) ~= 'table' then
    return nil
  end

  local ids = {}
  for key, value in pairs(choices) do
    local id = type(value) == 'table' and (value.modelId or value.id or key)
      or type(key) == 'number' and value
      or key
    ids[id] = true
  end
  return ids
end

local function unavailable_model(chat, model, ids)
  local available = vim.tbl_keys(ids or {})
  table.sort(available)
  vim.notify(
    string.format(
      'Model "%s" is not available for adapter "%s".%s',
      model,
      chat.adapter.name,
      #available > 0 and ('\nAvailable: ' .. table.concat(available, ', '))
        or ''
    ),
    vim.log.levels.ERROR
  )
end

-- One action owns a deferred model choice or picker. Later controls supersede it.
local function model_action(chat)
  chat._lpke_model_action = (chat._lpke_model_action or 0) + 1
  return chat._lpke_model_action
end

local function with_model_ready(chat, token, callback)
  local adapter, connection = chat.adapter, chat.acp_connection
  local swap = chat._lpke_adapter_swap
  local function valid()
    return registry.get(chat.bufnr) == chat
      and chat.adapter == adapter
      and chat._lpke_adapter_swap == swap
      and chat._lpke_model_action == token
      and (not connection or chat.acp_connection == connection)
  end
  if not M.is_acp_adapter(adapter) then
    if valid() then
      return callback(valid)
    end
    return
  end

  local lifecycle = require('lpke.plugins.ai.helpers.acp_lifecycle')
  local result
  lifecycle.ensure_chat_connection(chat, function()
    connection = connection or chat.acp_connection
    if
      valid()
      and connection
      and connection:is_connected()
      and not lifecycle.is_preparing(chat)
    then
      result = callback(valid)
    end
  end, { keep_visible = true })
  -- Native connection creation assigns its instance before yielding to the peer.
  connection = connection or chat.acp_connection
  return result
end

-- Set one model or cycle the supplied aliases, skipping unavailable choices.
function M.select(models, chat)
  chat = current_chat(chat)
  if not chat then
    return
  end
  models = type(models) == 'table' and models or { models }
  local token = model_action(chat)
  return with_model_ready(chat, token, function()
    local ids = available_model_ids(chat)
    local choices = vim.tbl_map(ai_config.model_id, models)
    local current = M.get_cur_model(chat.bufnr)
    local index = 0
    for i, model in ipairs(choices) do
      if model == current then
        index = i
        break
      end
    end
    for offset = 1, #choices do
      local target = choices[((index + offset - 1) % #choices) + 1]
      if not ids or ids[target] then
        chat:change_model({ model = target })
        return M.get_cur_model(chat.bufnr)
      end
    end
    if choices[1] then
      unavailable_model(chat, choices[1], ids)
    end
  end)
end

-- Preflight the native v20 vendor-state guard before disconnecting ACP.
-- Legacy saved tool_calls are also vendor-specific and must stay on the adapter.
function M.can_change_adapter(chat, target)
  if chat.adapter.name == target then
    return true
  end
  local state = vim.iter(chat.messages or {}):any(function(message)
    return message.reasoning ~= nil
      or message.tool_calls ~= nil
      or (message.tools and message.tools.calls ~= nil)
  end)
  if state then
    vim.notify(
      'Adapter cannot be changed after tool executions. Start a new chat to use `'
        .. target
        .. '`',
      vim.log.levels.WARN,
      { title = 'CodeCompanion' }
    )
    return false
  end
  return true
end

-- All adapter controls share suspension, defaults and callback ownership.
function M.change_adapter(chat, target, on_ready)
  chat = current_chat(chat)
  if not chat then
    return
  end
  local config = require('codecompanion.config')
  if not (config.adapters.acp[target] or config.adapters.http[target]) then
    vim.notify(
      'Adapter "' .. target .. '" is not configured.',
      vim.log.levels.ERROR
    )
    return
  end
  if not M.can_change_adapter(chat, target) then
    return
  end

  chat._lpke_adapter_swap = (chat._lpke_adapter_swap or 0) + 1
  local token = chat._lpke_adapter_swap
  local action = model_action(chat)
  local adapter, connection
  local function ready()
    if
      registry.get(chat.bufnr) ~= chat
      or chat._lpke_adapter_swap ~= token
      or chat._lpke_model_action ~= action
      or chat.adapter.name ~= target
      or (adapter and chat.adapter ~= adapter)
      or (connection and chat.acp_connection ~= connection)
    then
      return
    end
    return with_model_ready(chat, action, function(valid)
      if on_ready then
        return on_ready(valid)
      end
      local model = ai_config.adapter_default_model(target)
      if model and M.get_cur_model(chat.bufnr) ~= model then
        M.select(model, chat)
      end
    end)
  end

  if chat.adapter.name == target then
    ready()
  else
    if M.is_acp_adapter(chat.adapter) then
      require('lpke.plugins.ai.helpers.acp_lifecycle').suspend_chat(chat, {
        stop_request = true,
        delay_ms = 100,
        close_chat = false,
      })
    end
    if chat:change_adapter({ adapter = target, callback = ready }) == false then
      return
    end
    adapter, connection = chat.adapter, chat.acp_connection
  end
  return target
end

function M.cycle_adapters(adapters)
  local chat = current_chat()
  if not chat then
    return
  end
  adapters = type(adapters) == 'table' and adapters or { adapters }
  if #adapters == 0 then
    return
  end
  local index = 0
  for i, name in ipairs(adapters) do
    if name == chat.adapter.name then
      index = i
      break
    end
  end
  return M.change_adapter(chat, adapters[(index % #adapters) + 1])
end

function M.show_adapter_picker(chat)
  if require('codecompanion.config').display.chat.show_settings then
    return vim.notify(
      "Adapter can't be changed when settings are shown",
      vim.log.levels.WARN
    )
  end
  local ui = require('codecompanion.adapters.ui')
  ui.select_adapter({
    current = chat.adapter.name,
    on_choice = function(target)
      if not target then
        return
      end
      M.change_adapter(chat, target, function(valid)
        ui.select_model({
          adapter = chat.adapter,
          acp_models = chat.acp_connection and chat.acp_connection:get_models(),
          on_choice = function(model)
            if model and valid() then
              M.select(model, chat)
            end
          end,
        })
      end)
    end,
  })
end

return M
