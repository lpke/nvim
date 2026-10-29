local M = {}

local function normalize(value)
  return type(value) == 'string' and value:lower():gsub('[^%w]', '') or ''
end

local function is_full_access(value)
  local name = normalize(value)
  return name == 'agentfullaccess'
    or name == 'fullaccess'
    or name == 'dangerfullaccess'
end

local function resolve(connection, requested)
  if not is_full_access(requested) then
    return requested
  end

  local ACP = require('codecompanion.acp')
  for _, option in ipairs(connection:get_config_options()) do
    if option.category == 'mode' and option.type == 'select' then
      local values = ACP.flatten_config_options(option.options or {})
      -- Prefer IDs over labels, which changed between ACP 1.1.7 and 2.1.1.
      for _, id in ipairs({ requested, 'agent-full-access' }) do
        for _, value in ipairs(values) do
          if value.value == id then
            return value.value
          end
        end
      end
      for _, value in ipairs(values) do
        if is_full_access(value.value) then
          return value.value
        end
      end
      for _, value in ipairs(values) do
        local kind = vim.tbl_get(value, '_meta', 'jetbrains', 'air', 'kind')
        if is_full_access(value.name) or kind == 'full_access' then
          return value.value
        end
      end
    end
  end

  vim.notify(
    'Codex ACP has no matching Full Access mode; use <leader>a to check approvals',
    vim.log.levels.WARN,
    { title = 'CodeCompanion' }
  )
  return requested
end

function M.setup()
  local defaults = require('codecompanion.interactions.chat.acp.defaults')
  if defaults._lpke_codex_mode then
    return
  end
  defaults._lpke_codex_mode = true

  local original_apply = defaults.apply
  defaults.apply = function(adapter, connection)
    local options = adapter
      and adapter.defaults
      and adapter.defaults.session_config_options
    if not options or adapter.name ~= 'codex' or not options.mode then
      return original_apply(adapter, connection)
    end

    local mode = options.mode
    local adjusted = vim.tbl_extend('force', options, {
      -- Upstream invokes this after setting the model. Resolve against the
      -- latest advertised options without mutating shared adapter defaults.
      mode = function(current_adapter)
        local requested = mode
        if type(mode) == 'function' then
          requested = mode(current_adapter)
        end
        return resolve(connection, requested)
      end,
    })
    local adapter_defaults = vim.tbl_extend('force', adapter.defaults, {
      session_config_options = adjusted,
    })
    return original_apply(
      vim.tbl_extend('force', adapter, { defaults = adapter_defaults }),
      connection
    )
  end
end

return M
