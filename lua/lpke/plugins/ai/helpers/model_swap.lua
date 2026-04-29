local ai_config = require('lpke.plugins.ai.helpers.config')

local M = {}

function M.is_acp_adapter(adapter)
  return adapter and adapter.type == 'acp'
end

function M.is_codex_adapter(adapter)
  return M.is_acp_adapter(adapter) and adapter.name == 'codex'
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

  cur_chat:change_model({ model = target_model })
  return M.get_cur_model()
end

return M
