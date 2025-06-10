---@diagnostic disable: undefined-field
local helpers = require('lpke.core.helpers')
local tc = Lpke_theme_colors

-- restart all LSPs for the current buffer's filetype
function Lpke_lsp_restart()
  local current_ft = vim.bo.filetype
  if not current_ft or current_ft == '' then
    vim.notify('Lsp Restart: No filetype detected for current buffer', vim.log.levels.WARN)
    return
  end

  -- Get all active LSP clients for current buffer
  local clients = vim.lsp.get_clients({ bufnr = 0 })

  if #clients == 0 then
    vim.notify('Lsp Restart: No LSP clients active for current buffer', vim.log.levels.WARN)
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
  helpers.set_hl('diagnosticunnecessary', {})
  helpers.set_hl('diagnosticunderlineok', {})
  helpers.set_hl('diagnosticunderlinehint', {})
  helpers.set_hl('diagnosticunderlineinfo', {})
  helpers.set_hl('diagnosticunderlinewarn', {})
  helpers.set_hl('diagnosticunderlineerror', {})
end
function Lpke_show_diagnostic_hl()
  helpers.set_hl('diagnosticunnecessary', { fg = tc.subtleplus })
  helpers.set_hl('diagnosticunderlineok', { bg = tc.growthbg })
  helpers.set_hl('diagnosticunderlinehint', { bg = tc.irisbg })
  helpers.set_hl('diagnosticunderlineinfo', { bg = tc.foambg })
  helpers.set_hl('diagnosticunderlinewarn', { bg = tc.goldbg })
  helpers.set_hl('diagnosticunderlineerror', { bg = tc.lovebg })
end

function Lpke_dim_diagnostic_virtual_text()
  helpers.set_hl('diagnosticvirtualtextok', { fg = tc.growthbg, italic = true })
  helpers.set_hl('diagnosticvirtualtexthint', { fg = tc.irisbg, italic = true })
  helpers.set_hl('diagnosticvirtualtextinfo', { fg = tc.foambg, italic = true })
  helpers.set_hl('diagnosticvirtualtextwarn', { fg = tc.goldbg, italic = true })
  helpers.set_hl('diagnosticvirtualtexterror', { fg = tc.lovebg, italic = true })
end
function Lpke_show_diagnostic_virtual_text()
  helpers.set_hl('diagnosticvirtualtextok', { fg = tc.growth, italic = true })
  helpers.set_hl('diagnosticvirtualtexthint', { fg = tc.irisfaded, italic = true })
  helpers.set_hl('diagnosticvirtualtextinfo', { fg = tc.foamfaded, italic = true })
  helpers.set_hl('diagnosticvirtualtextwarn', { fg = tc.goldfaded, italic = true })
  helpers.set_hl('diagnosticvirtualtexterror', { fg = tc.lovefaded, italic = true })
end
-- stylua: ignore end

-- toggle LSP diagnostic highlighting globally
Lpke_diagnostics_hl_enabled = false
function Lpke_toggle_diagnostics_hl()
  local enabled = Lpke_diagnostics_hl_enabled
  if enabled then
    Lpke_hide_diagnostic_hl()
    Lpke_diagnostics_hl_enabled = false
  else
    Lpke_show_diagnostic_hl()
    Lpke_diagnostics_hl_enabled = true
  end
  pcall(function()
    require('lualine').refresh()
  end)
end

-- toggle LSP diagnostic virtual text globally
Lpke_diagnostics_virtual_text_enabled = true
function Lpke_toggle_diagnostics_virtual_text()
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
