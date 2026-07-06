local helpers = require('lpke.core.helpers')

local M = {}

M.unused_diagnostics_ignored = false

M.unused_diagnostic_codes = {
  6133, -- "'<name>' is declared but its value is never read"
  6138, -- "Property '<name>' is declared but its value is never read"
  6192, -- "All imports in import declaration are unused"
  6196, -- "'<name>' is declared but never used"
  6198, -- "All destructured elements are unused"
  6199, -- "All variables are unused"
  6205, -- "All type parameters are unused"
  7028, -- "Unused label"
  2578, -- "Unused '@ts-expect-error' directive"
}

M.static_settings = {
  implicitProjectConfiguration = {
    checkJs = true,
    module = 'ESNext',
    target = 'ES2024',
    strict = false,
    strictFunctionTypes = false,
    strictNullChecks = true,
  },
}

function M.dynamic_settings()
  return {
    diagnostics = {
      ignoredCodes = M.unused_diagnostics_ignored and M.unused_diagnostic_codes
        or {},
    },
  }
end

function M.settings()
  return vim.tbl_deep_extend(
    'force',
    {},
    M.static_settings,
    M.dynamic_settings()
  )
end

local function ignored_codes_lookup()
  local ignored_codes = {}

  for _, code in ipairs(M.unused_diagnostic_codes) do
    ignored_codes[code] = true
    ignored_codes[tostring(code)] = true
  end

  return ignored_codes
end

local function clear_visible_unused_diagnostics(client)
  local ignored_codes = ignored_codes_lookup()
  local namespace = vim.lsp.diagnostic.get_namespace(client.id)

  for _, bufnr in ipairs(vim.lsp.get_buffers_by_client_id(client.id)) do
    local diagnostics = vim.diagnostic.get(bufnr, { namespace = namespace })
    helpers.arr_filter_inplace(diagnostics, function(diag)
      return not ignored_codes[diag.code]
    end)
    vim.diagnostic.set(namespace, bufnr, diagnostics)
  end
end

function M.toggle_unused_diagnostics(choice)
  if choice ~= nil then
    M.unused_diagnostics_ignored = choice == false
  else
    M.unused_diagnostics_ignored = not M.unused_diagnostics_ignored
  end

  local settings = M.settings()
  pcall(vim.lsp.config, 'ts_ls', { settings = settings })

  local clients = vim.lsp.get_clients({ name = 'ts_ls' })
  for _, client in ipairs(clients) do
    client.config.settings =
      vim.tbl_deep_extend('force', client.config.settings or {}, settings)
    client.notify('workspace/didChangeConfiguration', {
      settings = client.config.settings,
    })

    if M.unused_diagnostics_ignored then
      clear_visible_unused_diagnostics(client)
    end
  end

  local status = M.unused_diagnostics_ignored and 'hidden' or 'visible'
  vim.notify('TypeScript unused diagnostics: ' .. status)
end

return M
