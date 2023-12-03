-- from copilot plugin
local function resolve_filetype_enabled(filetype_enabled)
  if type(filetype_enabled) == 'function' then
    return filetype_enabled()
  end
  return filetype_enabled
end
local function is_ft_disabled(ft, filetypes)
  if filetypes[ft] ~= nil then
    return not resolve_filetype_enabled(filetypes[ft])
  end
  local short_ft = string.gsub(ft, '%..*', '')
  if filetypes[short_ft] ~= nil then
    return not resolve_filetype_enabled(filetypes[short_ft])
  end
  if filetypes['*'] ~= nil then
    return not resolve_filetype_enabled(filetypes['*'])
  end
  return false
end

local function config()
  local copilot = require('copilot')
  local client = require('copilot.client')
  local cfg = require('copilot.config')
  local cmd = require('copilot.command')
  local sug = require('copilot.suggestion')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- detach copilot from buffer
  function Lpke_copilot_buf_detach(bufnr, client_id)
    local ok, result = pcall(function()
      bufnr = bufnr or 0
      local c_id = nil
      if client_id then
        c_id = client_id
      else
        c_id = vim.lsp.start(client.config)
      end
      Lpke_silent(function()
        vim.lsp.buf_detach_client(bufnr, c_id)
      end)
    end)
    if not ok then
      print('Error detaching buffer ' .. bufnr .. ': ' .. result)
    end
  end

  -- attach copilot to buffer
  function Lpke_copilot_buf_attach(bufnr, client_id, force)
    local ok, result = pcall(function()
      bufnr = bufnr or 0
      local c_id = nil
      if client_id then
        c_id = client_id
      else
        c_id = vim.lsp.start(client.config)
      end
      local should_attach = force
      local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
      should_attach = not is_ft_disabled(filetype, cfg.get('filetypes'))
      if should_attach or force then
        vim.lsp.buf_attach_client(bufnr, c_id)
      end
    end)
    if not ok then
      print('Error attaching buffer ' .. bufnr .. ': ' .. result)
    end
  end

  -- toggles github copilot globally (also apply to each buffer)
  function Lpke_toggle_copilot(bool)
    -- which direction to toggle is based on focused file's status
    local is_attached = client.buf_is_attached(0)
    -- :Copilot enable|disable (global)
    if bool == nil then
      if is_attached then
        cmd.disable()
      else
        cmd.enable()
      end
    else
      if bool == false then
        cmd.disable()
      else
        cmd.enable()
      end
    end
    -- :Copilot attach|detach (for each active buffer)
    local client_id = vim.lsp.start(client.config)
    local bufs = Lpke_get_active_bufs()
    for buf, _ in pairs(bufs) do
      if bool == nil then
        if is_attached then
          Lpke_copilot_buf_detach(buf, client_id)
        else
          Lpke_copilot_buf_attach(buf, client_id, cfg)
        end
      else
        if bool == false then
          Lpke_copilot_buf_detach(buf, client_id)
        else
          Lpke_copilot_buf_attach(buf, client_id, cfg)
        end
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
    {'i', '<F2>.', function()
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
      enabled = true,
      auto_refresh = false,
      keymap = {
        jump_prev = '[[',
        jump_next = ']]',
        accept = '<CR>',
        refresh = 'gr',
        open = '<F2>/',
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
        accept = '<F2>;',
        accept_word = false,
        accept_line = false,
        next = false, -- handled manually in keymaps above
        prev = '<F2>>',
        dismiss = '<F2>c',
      },
    },
    filetypes = {
      yaml = false,
      markdown = false,
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
    copilot_node_command = 'node', -- Node.js version must be > 18.x
    server_opts_overrides = {},
  })

  -- ensure copilot is activated on all active buffers after startup
  vim.defer_fn(function()
    Lpke_toggle_copilot(true)
  end, 1500)
end

return {
  'zbirenbaum/copilot.lua',
  event = 'InsertEnter',
  config = config,
}
