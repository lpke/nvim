local ts_diagnostics = require('lpke.lsp.helpers.ts_diagnostics')

local M = {}

-- Hacky workaround for TypeScript's default script-scope behavior for inferred JS projects.
-- Without this, JS files with no imports/exports can leak top-level names across files and hide missing imports.
M.force_module_detection_for_inferred_projects = true

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

function M.implicit_check_js_enabled(config)
  local implicit_config = (
    ((config or {}).settings or {}).implicitProjectConfiguration or {}
  )
  local check_js = implicit_config.checkJs
  if check_js == nil then
    check_js = M.static_settings.implicitProjectConfiguration.checkJs
  end

  return check_js == true
end

function M.dynamic_settings()
  return ts_diagnostics.dynamic_settings()
end

function M.settings()
  return vim.tbl_deep_extend(
    'force',
    {},
    M.static_settings,
    M.dynamic_settings()
  )
end

return M
