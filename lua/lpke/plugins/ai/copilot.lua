-- for interviews that disallow multi-line AI completions
local copilot_inline_single_line_only = false

local function first_line(text)
  if type(text) ~= 'string' then
    return ''
  end
  return text:match('^[^\r\n]*') or ''
end

local function trim_completion_to_single_line(completion)
  if type(completion) ~= 'table' then
    return nil
  end

  local text = first_line(completion.text)
  if text == '' then
    return nil
  end

  completion.text = text
  completion.displayText = first_line(completion.displayText)
  if completion.displayText == '' then
    completion.displayText = text
  end

  if type(completion.partial_text) == 'string' then
    completion.partial_text = first_line(completion.partial_text)
  end

  local range = completion.range
  if
    type(range) == 'table'
    and type(range.start) == 'table'
    and type(range['end']) == 'table'
  then
    if range['end'].line ~= range.start.line then
      range['end'].character = range.start.character
    end
    range['end'].line = range.start.line
  end

  return completion
end

local function trim_completions_to_single_line(data)
  if type(data) ~= 'table' or type(data.completions) ~= 'table' then
    return data
  end

  local completions = {}
  for _, completion in ipairs(data.completions) do
    completion = trim_completion_to_single_line(completion)
    if completion then
      table.insert(completions, completion)
    end
  end
  data.completions = completions

  return data
end

local function patch_copilot_inline_single_line(api)
  if
    not copilot_inline_single_line_only or api._lpke_inline_single_line_only
  then
    return
  end

  api._lpke_inline_single_line_only = true

  local get_completions = api.get_completions
  api.get_completions = function(client, params, callback)
    if type(callback) ~= 'function' then
      return get_completions(client, params, callback)
    end

    return get_completions(client, params, function(err, data, ...)
      return callback(err, trim_completions_to_single_line(data), ...)
    end)
  end

  local get_completions_cycling = api.get_completions_cycling
  api.get_completions_cycling = function(client, params, callback)
    if type(callback) ~= 'function' then
      return get_completions_cycling(client, params, callback)
    end

    return get_completions_cycling(client, params, function(err, data, ...)
      return callback(err, trim_completions_to_single_line(data), ...)
    end)
  end
end

local function config()
  local copilot = require('copilot')
  local api = require('copilot.api')
  local client = require('copilot.client')
  local cmd = require('copilot.command')
  local sug = require('copilot.suggestion')
  local helpers = require('lpke.core.helpers')
  local default_should_attach = require('copilot.config.should_attach').default
  local tc = Lpke_theme_colors

  patch_copilot_inline_single_line(api)

  -- detach copilot from buffer
  function Lpke_copilot_buf_detach(bufnr, client_id)
    local ok, result = pcall(function()
      bufnr = bufnr or 0
      bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      if client_id == nil then
        client.buf_detach_if_attached(bufnr)
        return
      end

      if type(client_id) ~= 'number' then
        return
      end

      Lpke_silent(function()
        vim.lsp.buf_detach_client(bufnr, client_id)
      end)
      require('copilot.suggestion').unset_keymap(bufnr)
      require('copilot.nes').unset_keymap(bufnr)
    end)
    if not ok then
      vim.notify(
        'Error detaching buffer ' .. bufnr .. ': ' .. result,
        vim.log.levels.ERROR
      )
    end
  end

  -- attach copilot to buffer
  function Lpke_copilot_buf_attach(bufnr, client_id, force)
    local ok, result = pcall(function()
      bufnr = bufnr or 0
      bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

      if
        not vim.api.nvim_buf_is_valid(bufnr)
        or helpers.get_git_buf_type(bufnr) == 'diffview'
      then
        return
      end

      if client_id == nil then
        client.buf_attach(force == true, bufnr)
        return
      end

      if type(client_id) ~= 'number' then
        return
      end

      vim.lsp.buf_attach_client(bufnr, client_id)
      require('copilot.suggestion').set_keymap(bufnr)
      require('copilot.nes').set_keymap(bufnr)
    end)
    if not ok then
      vim.notify(
        'Error attaching buffer ' .. bufnr .. ': ' .. result,
        vim.log.levels.ERROR
      )
    end
  end

  -- toggles github copilot globally (also apply to each buffer)
  function Lpke_toggle_copilot(bool)
    -- which direction to toggle is based on focused file's status
    local is_attached = client.buf_is_attached(0)
    local should_disable = (bool == false) or (bool == nil and is_attached)

    if should_disable then
      -- disable globally and detach all buffers
      cmd.disable()
    else
      -- enable globally only if currently disabled (avoid restart)
      if client.is_disabled() then
        cmd.enable()
      end
      -- attach to all active buffers
      local bufs = Lpke_get_active_bufs()
      for buf, _ in pairs(bufs) do
        Lpke_copilot_buf_attach(buf)
      end
    end
    -- update lualine
    pcall(function()
      require('lualine').refresh()
    end)
  end

  -- theme
  helpers.set_hl('CopilotAnnotation', { fg = tc.mutedminus })

  -- stylua: ignore start
  helpers.keymap_set_multi({
    {'nv', '<F2>C', Lpke_toggle_copilot, { desc = 'Toggle copilot for all buffers' }},
    {'nv', '<A-C>', Lpke_toggle_copilot, { desc = 'Toggle copilot for all buffers' }},
    {'i', '<F2>.', function()
      local is_attached = client.buf_is_attached(0)
      if not is_attached then
        Lpke_copilot_buf_attach(0)
        Lpke_feedkeys('<Space><BS>', 'tn')
      end
      sug.next()
    end, { desc = 'Copilot: Trigger/next suggestion' }},
    {'i', '<A-.>', function()
      local is_attached = client.buf_is_attached(0)
      if not is_attached then
        Lpke_copilot_buf_attach(0)
        Lpke_feedkeys('<Space><BS>', 'tn')
      end
      sug.next()
    end, { desc = 'Copilot: Trigger/next suggestion' }},
  })
  -- stylua: ignore end

  copilot.setup({
    panel = {
      enabled = not copilot_inline_single_line_only,
      auto_refresh = false,
      keymap = {
        jump_prev = '[[',
        jump_next = ']]',
        accept = '<CR>',
        refresh = 'gr',
        -- open = '<F2>/', -- FIXME?
        open = '<A-/>',
      },
      layout = {
        position = 'bottom', -- | top | left | right
        ratio = 0.4,
      },
    },
    suggestion = {
      enabled = true,
      auto_trigger = false,
      debounce = 75,
      keymap = {
        -- accept = '<F2>;', -- FIXME?
        accept = '<A-;>',
        accept_word = false,
        accept_line = false,
        next = false, -- handled manually in keymaps above
        -- prev = '<F2>>', -- FIXME?
        prev = '<A->>',
        -- dismiss = '<F2>c', -- FIXME?
        dismiss = '<A-c>',
      },
    },
    filetypes = {
      markdown = true,
      codecompanion = true,
      codecompanion_input = true,
      yaml = false,
      help = false,
      gitcommit = false,
      gitrebase = false,
      hgcommit = false,
      svn = false,
      cvs = false,
      oil = false,
      fugitive = false,
      ['.'] = false,
    },
    copilot_node_command = 'node',
    should_attach = function(bufnr, bufname)
      if helpers.get_git_buf_type(bufnr) == 'diffview' then
        return false
      end
      return default_should_attach(bufnr, bufname)
    end,
    server_opts_overrides = {},
  })

  -- ensure copilot is attached to all active buffers after startup
  vim.defer_fn(function()
    local bufs = Lpke_get_active_bufs()
    for buf, _ in pairs(bufs) do
      Lpke_copilot_buf_attach(buf)
    end
    pcall(function()
      require('lualine').refresh()
    end)
  end, 1500)
end

return {
  'zbirenbaum/copilot.lua',
  commit = 'ad7e729e9a6348f7da482be0271d452dbc4c8e2c',
  event = 'InsertEnter',
  config = config,
}
