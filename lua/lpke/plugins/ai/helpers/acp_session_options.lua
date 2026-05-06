local ai_config = require('lpke.plugins.ai.helpers.config')
local model_swap = require('lpke.plugins.ai.helpers.model_swap')

local M = {}

local function normalize(value)
  return tostring(value or ''):lower():gsub('[%s_-]+', ' ')
end

local function adapter_config(adapter)
  if not model_swap.is_acp_adapter(adapter) then
    return nil
  end

  return ai_config.acp_session_options.adapters[adapter.name]
end

local function find_option(options, option_config)
  local exact_ids = {}
  for _, id in ipairs(option_config.exact_ids or {}) do
    exact_ids[id] = true
  end

  for _, opt in ipairs(options or {}) do
    if exact_ids[opt.id] then
      return opt
    end
  end

  for _, opt in ipairs(options or {}) do
    local haystack = table.concat({
      normalize(opt.id),
      normalize(opt.name),
      normalize(opt.description),
      normalize(opt.category),
    }, ' ')

    for _, pattern in ipairs(option_config.patterns or {}) do
      if haystack:find(pattern) then
        return opt
      end
    end
  end
end

function M.get_current_value(kind, bufnr)
  local chat = model_swap.get_chat_ref(bufnr or 0)
  local config = chat and adapter_config(chat.adapter)
  local option_config = config and config.options and config.options[kind]
  if not option_config or not chat.acp_connection then
    return nil
  end

  local options = chat.acp_connection:get_config_options({
    exclude_categories = { 'model' },
  })
  local option = find_option(options, option_config)
  if not option or option.currentValue == nil then
    return nil
  end

  for _, value in
    ipairs(
      require('codecompanion.acp').flatten_config_options(option.options or {})
    )
  do
    if value.value == option.currentValue then
      return value.name or value.value
    end
  end

  return option.currentValue
end

function M.show(kind)
  if vim.bo.filetype ~= 'codecompanion' then
    return vim.notify(
      'ACP session options are only available in CodeCompanion chats',
      vim.log.levels.WARN
    )
  end

  local chat = model_swap.get_chat_ref(0)
  local config = chat and adapter_config(chat.adapter)
  if not config then
    return vim.notify(
      'ACP session options keymap is not configured for this adapter',
      vim.log.levels.WARN
    )
  end

  local option_config = config.options and config.options[kind]
  if not option_config then
    return vim.notify(
      string.format(
        '%s has no configured ACP %s option',
        config.display or chat.adapter.name,
        kind
      ),
      vim.log.levels.WARN
    )
  end

  require('lpke.plugins.ai.helpers.acp_lifecycle').ensure_chat_connection(
    chat,
    function()
      local options = chat.acp_connection
          and chat.acp_connection:get_config_options({
            exclude_categories = { 'model' },
          })
        or {}
      local option = find_option(options, option_config)

      if not option then
        return vim.notify(
          string.format(
            'No %s %s option is available for this model',
            config.display or chat.adapter.name,
            option_config.display or kind
          ),
          vim.log.levels.WARN
        )
      end

      local SlashCommand = require(
        'codecompanion.interactions.chat.slash_commands.builtin.acp_session_options'
      )
      SlashCommand.new({
        Chat = chat,
        config = {},
        context = {},
      }):show_values(option)
    end,
    { keep_visible = true }
  )
end

function M.show_reasoning()
  return M.show('reasoning')
end

function M.show_approval()
  return M.show('approval')
end

return M
