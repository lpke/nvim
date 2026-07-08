local helpers = require('lpke.core.helpers')

local M = {}

local function codes_lookup(codes)
  local lookup = {}

  for _, code in ipairs(codes) do
    lookup[code] = true
    lookup[tostring(code)] = true
  end

  return lookup
end

M.unused_diagnostics_ignored = false

-- Hacky workaround for TypeScript's default script-scope behavior for inferred JS projects.
-- Without this, JS files with no imports/exports can leak top-level names across files and hide missing imports.
M.force_module_detection_for_inferred_projects = true

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

M.js_ignored_diagnostic_codes = {
  -- type annotation / TypeScript conversion suggestions
  7043, -- "Variable '<name>' implicitly has an '<type>' type, but a better type may be inferred from usage"
  7044, -- "Parameter '<name>' implicitly has an '<type>' type, but a better type may be inferred from usage"
  7045, -- "Member '<name>' implicitly has an '<type>' type, but a better type may be inferred from usage"
  7046, -- "Variable '<name>' implicitly has type '<type>' in some locations, but a better type may be inferred from usage"
  7047, -- "Rest parameter '<name>' implicitly has an 'any[]' type, but a better type may be inferred from usage"
  7048, -- "Property '<name>' implicitly has type 'any', but a better type for its get accessor may be inferred from usage"
  7049, -- "Property '<name>' implicitly has type 'any', but a better type for its set accessor may be inferred from usage"
  7050, -- "'<name>' implicitly has an '<type>' return type, but a better type may be inferred from usage"
  80001, -- "File is a CommonJS module; it may be converted to an ES module"
  80002, -- "This constructor function may be converted to a class declaration"
  80003, -- "Import may be converted to a default import"
  80004, -- "JSDoc types may be moved to TypeScript types"
  80005, -- "'require' call may be converted to an import"
  80006, -- "This may be converted to an async function"
  80009, -- "JSDoc typedef may be converted to TypeScript type"
  80010, -- "JSDoc typedefs may be converted to TypeScript types"
}

M.unused_diagnostic_codes_lookup = codes_lookup(M.unused_diagnostic_codes)
M.js_ignored_diagnostic_codes_lookup =
  codes_lookup(M.js_ignored_diagnostic_codes)

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

local function clear_visible_unused_diagnostics(client)
  local namespace = vim.lsp.diagnostic.get_namespace(client.id)

  for _, bufnr in ipairs(vim.lsp.get_buffers_by_client_id(client.id)) do
    local diagnostics = vim.diagnostic.get(bufnr, { namespace = namespace })
    helpers.arr_filter_inplace(diagnostics, function(diag)
      return not M.unused_diagnostic_codes_lookup[diag.code]
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
