local M = {}

local prompt_dir = '/home/luke/.local/share/ai-lib/caveman/prompts'

local levels = {
  lite = true,
  full = true,
  ultra = true,
}

local state = {
  enabled = true,
  level = 'lite',
}

local prompt_cache = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, {
    title = 'CodeCompanion Caveman',
  })
end

local function has_system_prompt(chat)
  return vim.tbl_contains(
    vim.tbl_map(function(msg)
      return msg._meta and msg._meta.tag
    end, chat.messages or {}),
    'system_prompt_from_config'
  )
end

local function read_prompt(level)
  if prompt_cache[level] ~= nil then
    return prompt_cache[level]
  end

  local path = vim.fs.joinpath(prompt_dir, level .. '.md')
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then
    prompt_cache[level] = false
    return nil
  end

  local prompt = vim.trim(table.concat(lines, '\n'))
  prompt_cache[level] = prompt ~= '' and prompt or false
  return prompt_cache[level] or nil
end

local function http_adapter(ctx)
  local adapter = ctx and ctx.adapter
  return type(adapter) == 'table' and adapter.type == 'http'
end

local function adapter_name(adapter)
  return adapter and (adapter.formatted_name or adapter.name or adapter.type)
    or 'LLM'
end

local function default_llm_role(adapter)
  return 'CodeCompanion (' .. adapter_name(adapter) .. ')'
end

local function caveman_llm_role(adapter, level)
  return 'CodeCompanion ('
    .. adapter_name(adapter)
    .. ', caveman: '
    .. level
    .. ')'
end

function M.http_chat(chat)
  local adapter = chat and chat.adapter
  return type(adapter) == 'table' and adapter.type == 'http'
end

function M.enabled()
  return state.enabled
end

function M.level()
  return state.level
end

function M.llm_role(adapter)
  if
    type(adapter) ~= 'table'
    or adapter.type ~= 'http'
    or not state.enabled
  then
    return default_llm_role(adapter)
  end

  return caveman_llm_role(adapter, state.level)
end

function M.set(level)
  if level == 'off' then
    state.enabled = false
    return true
  end

  if not levels[level] then
    return false
  end

  if not read_prompt(level) then
    notify(
      'Missing caveman prompt: ' .. vim.fs.joinpath(prompt_dir, level .. '.md'),
      vim.log.levels.ERROR
    )
    return false
  end

  state.enabled = true
  state.level = level
  return true
end

function M.system_prompt(ctx)
  local base = ctx.default_system_prompt
    .. string.format(
      [[Additional context:
All non-code text responses must be written in the %s language.
The user's current working directory is %s.
The current date is %s.
The user's Neovim version is %s.
The user is working on a %s machine. Please respond with system specific commands if applicable.
]],
      ctx.language,
      ctx.cwd,
      ctx.date,
      ctx.nvim_version,
      ctx.os
    )

  if not state.enabled or not http_adapter(ctx) then
    return base
  end

  local prompt = read_prompt(state.level)
  if not prompt then
    return base
  end

  return base
    .. '\n\n'
    .. 'Caveman response mode is enabled. Apply these additional response-style rules:\n\n'
    .. prompt
end

function M.refresh_system_prompt(chat)
  if not chat then
    return
  end

  if
    chat.messages
    and not (chat.opts and chat.opts.ignore_system_prompt)
    and has_system_prompt(chat)
  then
    chat:set_system_prompt()
  end
end

function M.slash(chat)
  if not M.http_chat(chat) then
    notify('/caveman only works with HTTP adapters', vim.log.levels.WARN)
    return
  end

  local choices = {
    'off',
    'lite',
    'full',
    'ultra',
  }

  vim.ui.select(choices, {
    prompt = '/caveman - Select mode:',
    format_item = function(choice)
      local label = choice
      if choice ~= 'off' and state.enabled and state.level == choice then
        label = '* ' .. label
      elseif choice == 'off' and not state.enabled then
        label = '* ' .. label
      else
        label = '  ' .. label
      end
      return label
    end,
  }, function(choice)
    if not choice then
      return
    end

    if not M.set(choice) then
      return
    end

    M.refresh_system_prompt(chat)

    if choice == 'off' then
      notify('Caveman mode disabled')
    else
      notify('Caveman mode enabled: ' .. choice)
    end
  end)
end

return M
