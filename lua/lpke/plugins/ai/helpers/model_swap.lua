local ai_config = require('lpke.plugins.ai.helpers.config')

local M = {}

function M.is_acp_adapter(adapter)
  return adapter and adapter.type == 'acp'
end

function M.is_http_adapter(adapter)
  return adapter and adapter.type == 'http'
end

function M.is_codex_adapter(adapter)
  return M.is_acp_adapter(adapter) and adapter.name == 'codex'
end

local function adapter_name(adapter)
  return adapter and (adapter.name or adapter.formatted_name or adapter.type)
    or 'unknown'
end

local function resolve_http_model_choices(adapter)
  local model_schema = adapter and adapter.schema and adapter.schema.model
  local choices = model_schema and model_schema.choices

  if type(choices) == 'function' then
    local ok, resolved = pcall(choices, adapter, { async = false })
    if not ok then
      ok, resolved = pcall(choices, adapter)
    end
    choices = ok and resolved or nil
  end

  return choices
end

local function model_choice_id(key, value)
  if type(value) == 'table' then
    return value.id or value.modelId or key
  end

  if type(key) == 'number' then
    return value
  end

  return key
end

local function available_model_ids(chat)
  if not chat or not chat.adapter then
    return nil
  end

  local adapter = chat.adapter
  local ids = {}

  if M.is_acp_adapter(adapter) then
    local models = chat.acp_connection and chat.acp_connection:get_models()
    if not models or type(models.availableModels) ~= 'table' then
      return nil
    end

    for _, model in ipairs(models.availableModels) do
      local id = type(model) == 'table' and model.modelId or model
      if id then
        ids[id] = true
      end
    end

    return ids
  end

  if M.is_http_adapter(adapter) then
    local choices = resolve_http_model_choices(adapter)
    if type(choices) ~= 'table' then
      return nil
    end

    for key, value in pairs(choices) do
      local id = model_choice_id(key, value)
      if type(id) == 'string' then
        ids[id] = true
      end
    end

    return ids
  end
end

function M.is_model_available(chat, model)
  local ids = available_model_ids(chat)
  if not ids then
    return true
  end

  return ids[model] == true, ids
end

function M.notify_unavailable_model(chat, model, ids)
  local available = vim.tbl_keys(ids or {})
  table.sort(available)

  local suffix = ''
  if #available > 0 then
    suffix = '\nAvailable: ' .. table.concat(available, ', ')
  end

  vim.notify(
    string.format(
      'Model "%s" is not available for adapter "%s".%s',
      model,
      adapter_name(chat and chat.adapter),
      suffix
    ),
    vim.log.levels.ERROR
  )
end

function M.get_chat_ref(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  return require('codecompanion').buf_get_chat(bufnr)
end

function M.get_cur_model(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local chat = require('codecompanion').buf_get_chat(bufnr)
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

  return adapter.schema.model.default or adapter.opts.model
end

function M.get_cur_adapter(bufnr)
  local chat = M.get_chat_ref(bufnr)
  return chat and chat.adapter and chat.adapter.name
end

function M.is_adapter_configured(adapter)
  local cc_config = require('codecompanion.config')
  return (cc_config.adapters.acp and cc_config.adapters.acp[adapter])
    or (cc_config.adapters.http and cc_config.adapters.http[adapter])
end

function M.get_cur_acp_mode(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local chat = require('codecompanion').buf_get_chat(bufnr)
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

function M.is_acp_chat(bufnr)
  local chat = M.get_chat_ref(bufnr)
  return chat and M.is_acp_adapter(chat.adapter)
end

function M.is_http_chat(bufnr)
  local chat = M.get_chat_ref(bufnr)
  return chat and M.is_http_adapter(chat.adapter)
end

function M.is_codex_chat(bufnr)
  local chat = M.get_chat_ref(bufnr)
  return chat and M.is_codex_adapter(chat.adapter)
end

-- cycle through AI models provided in an array (or apply directly if only one)
-- returns name of model swapped to, or nil if error
function Lpke_cc_model(models)
  if vim.bo.filetype ~= 'codecompanion' then
    vim.notify(
      'Lpke_cc_model_swap: Not in a CodeCompanion chat buffer',
      vim.log.levels.ERROR
    )
    return nil
  end
  local cur_chat = M.get_chat_ref(0)
  if not cur_chat then
    return nil
  end

  -- Normalize input to array
  if type(models) ~= 'table' then
    models = { models }
  end

  -- Resolve all model names through the shared AI config
  local resolved_models = {}
  for i, m in ipairs(models) do
    resolved_models[i] = ai_config.model_id(m)
  end

  local cur_model = M.get_cur_model(0)

  local target_model
  if #resolved_models == 1 then
    -- Only one model provided - apply it directly
    target_model = resolved_models[1]
  else
    -- Multiple models - find current and cycle to next
    local cur_index = nil
    for i, m in ipairs(resolved_models) do
      if m == cur_model then
        cur_index = i
        break
      end
    end
    -- Cycle to next model (or first if not found/at end)
    if cur_index and cur_index < #resolved_models then
      target_model = resolved_models[cur_index + 1]
    else
      target_model = resolved_models[1]
    end
  end

  local ok, ids = M.is_model_available(cur_chat, target_model)
  if not ok then
    M.notify_unavailable_model(cur_chat, target_model, ids)
    return nil
  end

  cur_chat:change_model({ model = target_model })
  return M.get_cur_model()
end

-- cycle through AI adapters provided in an array (or apply directly if only one)
-- returns name of adapter swapped to, or nil if error
function Lpke_cc_adapter(adapters)
  if vim.bo.filetype ~= 'codecompanion' then
    vim.notify(
      'Lpke_cc_adapter_swap: Not in a CodeCompanion chat buffer',
      vim.log.levels.ERROR
    )
    return nil
  end
  local cur_chat = M.get_chat_ref(0)
  if not cur_chat then
    return nil
  end

  if type(adapters) ~= 'table' then
    adapters = { adapters }
  end

  local cur_adapter = M.get_cur_adapter(0)
  local from_adapter = cur_chat.adapter

  local target_adapter
  if #adapters == 1 then
    target_adapter = adapters[1]
  else
    local cur_index = nil
    for i, adapter in ipairs(adapters) do
      if adapter == cur_adapter then
        cur_index = i
        break
      end
    end
    if cur_index and cur_index < #adapters then
      target_adapter = adapters[cur_index + 1]
    else
      target_adapter = adapters[1]
    end
  end

  if not target_adapter then
    return nil
  end

  if not M.is_adapter_configured(target_adapter) then
    vim.notify(
      string.format('Adapter "%s" is not configured.', target_adapter),
      vim.log.levels.ERROR
    )
    return nil
  end

  local default_model = ai_config.adapter_default_model(target_adapter)

  local function on_adapter_ready()
    require('lpke.plugins.ai.helpers.chat_functions').sync_http_tools_for_adapter_change(
      cur_chat.bufnr,
      from_adapter,
      cur_chat.adapter
    )

    require('lpke.plugins.ai.helpers.caveman').refresh_system_prompt(cur_chat)

    if default_model then
      local ok, ids = M.is_model_available(cur_chat, default_model)
      if not ok then
        M.notify_unavailable_model(cur_chat, default_model, ids)
        return
      end

      cur_chat:change_model({ model = default_model })
    end
  end

  if cur_adapter ~= target_adapter then
    require('lpke.plugins.ai.helpers.acp_lifecycle').suspend_chat(cur_chat, {
      stop_request = true,
      delay_ms = 100,
    })
    cur_chat:change_adapter(target_adapter, on_adapter_ready)
  else
    on_adapter_ready()
  end

  return target_adapter
end

return M
