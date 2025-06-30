---@diagnostic disable: undefined-field
local helpers = require('lpke.core.helpers')
local tc = Lpke_theme_colors

-- restart all LSPs for the current buffer's filetype
function Lpke_lsp_restart()
  local current_ft = vim.bo.filetype
  if not current_ft or current_ft == '' then
    vim.notify(
      'Lsp Restart: No filetype detected for current buffer',
      vim.log.levels.WARN
    )
    return
  end

  -- Get all active LSP clients for current buffer
  local clients = vim.lsp.get_clients({ bufnr = 0 })

  if #clients == 0 then
    vim.notify(
      'Lsp Restart: No LSP clients active for current buffer',
      vim.log.levels.WARN
    )
    return
  end

  local restarted = {}

  for _, client in ipairs(clients) do
    -- Check if client's filetypes include current filetype
    if client.config and client.config.filetypes then
      for _, ft in ipairs(client.config.filetypes) do
        if ft == current_ft then
          vim.cmd('LspRestart ' .. client.name)
          table.insert(restarted, client.name)
          break
        end
      end
    end
  end

  if #restarted > 0 then
    vim.notify('Restarted LSP servers: ' .. table.concat(restarted, ', '))
  end
end

-- toggle LSP diagnostics globally
Lpke_diagnostics_enabled_initial = true
Lpke_diagnostics_enabled_prev = nil
function Lpke_toggle_diagnostics(choice)
  -- getting and storing current state
  local enabled = vim.diagnostic.is_enabled()
  Lpke_diagnostics_enabled_prev = enabled

  -- manual choice
  if choice ~= nil then
    if choice == false then
      pcall(vim.diagnostic.enable, false)
    elseif choice == true then
      pcall(vim.diagnostic.enable)
    elseif choice == 'prev' then
      if Lpke_diagnostics_enabled_prev == true then
        pcall(vim.diagnostic.enable)
      else
        pcall(vim.diagnostic.enable, false)
      end
    else
      vim.notify(
        'Diagnostics toggle: invalid argument:'
          .. ' `'
          .. tostring(choice)
          .. '` ('
          .. type(choice)
          .. ')',
        vim.log.levels.WARN
      )
    end
    pcall(function()
      require('lualine').refresh()
    end)
    return
  end

  -- toggle based on previous state
  if enabled then
    pcall(vim.diagnostic.enable, false)
  else
    pcall(vim.diagnostic.enable)
  end
  pcall(function()
    require('lualine').refresh()
  end)
end

-- stylua: ignore start
function Lpke_hide_diagnostic_hl()
  helpers.set_hl('DiagnosticUnnecessary', {})
  helpers.set_hl('DiagnosticUnderlineOk', {})
  helpers.set_hl('DiagnosticUnderlineHint', {})
  helpers.set_hl('DiagnosticUnderlineInfo', {})
  helpers.set_hl('DiagnosticUnderlineWarn', {})
  helpers.set_hl('DiagnosticUnderlineError', {})
end
function Lpke_show_diagnostic_hl()
  helpers.set_hl('DiagnosticUnnecessary', { fg = tc.subtleplus })
  helpers.set_hl('DiagnosticUnderlineOk', { bg = tc.growthbg })
  helpers.set_hl('DiagnosticUnderlineHint', { bg = tc.irisbg })
  helpers.set_hl('DiagnosticUnderlineInfo', { bg = tc.foambg })
  helpers.set_hl('DiagnosticUnderlineWarn', { bg = tc.goldbg })
  helpers.set_hl('DiagnosticUnderlineError', { bg = tc.lovebg })
end

function Lpke_dim_diagnostic_virtual_text()
  helpers.set_hl('DiagnosticVirtualTextOk', { fg = tc.growthbg, italic = true })
  helpers.set_hl('DiagnosticVirtualTextHint', { fg = tc.irisbg, italic = true })
  helpers.set_hl('DiagnosticVirtualTextInfo', { fg = tc.foambg, italic = true })
  helpers.set_hl('DiagnosticVirtualTextWarn', { fg = tc.goldbg, italic = true })
  helpers.set_hl('DiagnosticVirtualTextError', { fg = tc.lovebg, italic = true })
  helpers.set_hl('DiagnosticVirtualLinesOk', { fg = tc.growthbg, italic = true })
  helpers.set_hl('DiagnosticVirtualLinesHint', { fg = tc.irisbg, italic = true })
  helpers.set_hl('DiagnosticVirtualLinesInfo', { fg = tc.foambg, italic = true })
  helpers.set_hl('DiagnosticVirtualLinesWarn', { fg = tc.goldbg, italic = true })
  helpers.set_hl('DiagnosticVirtualLinesError', { fg = tc.lovebg, italic = true })
end
function Lpke_show_diagnostic_virtual_text()
  helpers.set_hl('DiagnosticVirtualTextOk', { fg = tc.growth, italic = true })
  helpers.set_hl('DiagnosticVirtualTextHint', { fg = tc.irisfaded, italic = true })
  helpers.set_hl('DiagnosticVirtualTextInfo', { fg = tc.foamfaded, italic = true })
  helpers.set_hl('DiagnosticVirtualTextWarn', { fg = tc.goldfaded, italic = true })
  helpers.set_hl('DiagnosticVirtualTextError', { fg = tc.lovefaded, italic = true })
  helpers.set_hl('DiagnosticVirtualLinesOk', { fg = tc.growth, italic = true })
  helpers.set_hl('DiagnosticVirtualLinesHint', { fg = tc.irisfaded, italic = true })
  helpers.set_hl('DiagnosticVirtualLinesInfo', { fg = tc.foamfaded, italic = true })
  helpers.set_hl('DiagnosticVirtualLinesWarn', { fg = tc.goldfaded, italic = true })
  helpers.set_hl('DiagnosticVirtualLinesError', { fg = tc.lovefaded, italic = true })
end
-- stylua: ignore end

-- toggle LSP diagnostic highlighting globally
-- also toggles virtual lines
Lpke_diagnostics_hl_enabled = false
function Lpke_toggle_diagnostics_hl()
  local enabled = Lpke_diagnostics_hl_enabled
  if enabled then
    Lpke_hide_diagnostic_hl()
    vim.diagnostic.config({
      virtual_lines = false,
      virtual_text = Lpke_diagnostic_config.virtual_text,
    })
    Lpke_diagnostics_hl_enabled = false
  else
    Lpke_show_diagnostic_hl()
    vim.diagnostic.config({ virtual_lines = true, virtual_text = false })
    Lpke_diagnostics_hl_enabled = true
  end
  pcall(function()
    require('lualine').refresh()
  end)
end

-- toggle virtual text for current line only
function Lpke_toggle_virtual_text_current_line()
  local cur_config = vim.diagnostic.config() or {}
  if
    (cur_config.virtual_lines == true)
    or (type(cur_config.virtual_text) == 'boolean')
  then
    return
  end
  vim.diagnostic.config({
    virtual_text = vim.tbl_extend(
      'force',
      Lpke_diagnostic_config.virtual_text,
      {
        current_line = not cur_config.virtual_text.current_line,
      }
    ),
  })
end

-- toggle virtual text
function Lpke_toggle_virtual_text()
  local cur_config = vim.diagnostic.config() or {}
  if cur_config.virtual_text == false then
    vim.diagnostic.config({
      virtual_text = Lpke_diagnostic_config.virtual_text,
    })
  else
    vim.diagnostic.config({
      virtual_text = false,
    })
  end
end

-- toggle LSP diagnostic virtual text globally
Lpke_diagnostics_virtual_text_enabled = true
function Lpke_toggle_dim_virtual_text()
  local enabled = Lpke_diagnostics_virtual_text_enabled
  if enabled then
    Lpke_dim_diagnostic_virtual_text()
    Lpke_diagnostics_virtual_text_enabled = false
  else
    Lpke_show_diagnostic_virtual_text()
    Lpke_diagnostics_virtual_text_enabled = true
  end
  pcall(function()
    require('lualine').refresh()
  end)
end
