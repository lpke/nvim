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

local function is_javascript_filetype(filetype)
  return filetype == 'javascript'
    or filetype == 'javascriptreact'
    or filetype == 'javascript.jsx'
    or filetype == 'js'
    or filetype == 'jsx'
end

local function diagnostic_bufnr(result, ctx)
  if ctx and ctx.bufnr then
    return ctx.bufnr
  end
  if result and result.uri then
    return vim.uri_to_bufnr(result.uri)
  end
end

local function filter_context(result, ctx)
  local client = ctx
      and ctx.client_id
      and vim.lsp.get_client_by_id(ctx.client_id)
    or nil
  local bufnr = diagnostic_bufnr(result, ctx)

  return {
    bufnr = bufnr,
    client = client,
    is_javascript = bufnr ~= nil
      and vim.api.nvim_buf_is_valid(bufnr)
      and is_javascript_filetype(vim.bo[bufnr].filetype),
    is_inferred_check_js_project = client
        and client.config
        and client.config.lpke_is_inferred_check_js_project
      or false,
    is_ts_ls = client ~= nil and client.name == 'ts_ls',
  }
end

M.inferred_mode = 'relaxed'
M.unused_diagnostics_ignored = false

-- Suggestions about adding types or converting JavaScript to TypeScript are
-- noise even when full inferred-project diagnostics are enabled.
M.js_always_ignored_codes = {
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

M.relaxed_allowed_codes = {
  2304, -- Cannot find name
  2307, -- Cannot find module
  2349, -- This expression is not callable
  2351, -- This expression is not constructable
  2451, -- Cannot redeclare block-scoped variable
  2551, -- Property does not exist; did you mean another property?
  2552, -- Cannot find name; did you mean another name?
  2554, -- Wrong argument count
  2588, -- Cannot assign to a const
  2632, -- Cannot assign to an import
  2792, -- Cannot find module (classic module resolution variant)
  18004, -- No value exists for a shorthand property
}

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

M.js_always_ignored_codes_lookup = codes_lookup(M.js_always_ignored_codes)
M.relaxed_allowed_codes_lookup = codes_lookup(M.relaxed_allowed_codes)
M.unused_diagnostic_codes_lookup = codes_lookup(M.unused_diagnostic_codes)

-- Latest unfiltered inferred-project result per client and document. This lets
-- the display mode change immediately without restarting or editing a buffer.
local cached_results = {}

function M.should_keep(diag, is_inferred_check_js_project)
  local code = tonumber(diag.code)

  if
    M.unused_diagnostics_ignored
    and M.unused_diagnostic_codes_lookup[diag.code]
  then
    return false
  end

  if M.js_always_ignored_codes_lookup[diag.code] then
    return false
  end

  if not is_inferred_check_js_project or M.inferred_mode == 'full' then
    return true
  end

  if code and code >= 1000 and code <= 1999 then
    return true
  end

  return M.relaxed_allowed_codes_lookup[diag.code] == true
end

local function filter_result(result, ctx)
  helpers.arr_filter_inplace(result.diagnostics, function(diag)
    return M.should_keep(diag, ctx.is_inferred_check_js_project)
  end)
end

local function cache_result(result, ctx)
  if not ctx.is_inferred_check_js_project or not result.uri then
    return
  end

  local client_results = cached_results[ctx.client.id] or {}
  client_results[result.uri] = {
    bufnr = ctx.bufnr,
    result = vim.deepcopy(result),
  }
  cached_results[ctx.client.id] = client_results
end

function M.filter(result, lsp_ctx)
  local ctx = filter_context(result, lsp_ctx)
  if not ctx.is_ts_ls or not ctx.is_javascript then
    return
  end

  cache_result(result, ctx)
  filter_result(result, ctx)
end

local function refresh_cached_results()
  for client_id, client_results in pairs(cached_results) do
    local client = vim.lsp.get_client_by_id(client_id)
    if client and not client:is_stopped() then
      for uri, cached in pairs(client_results) do
        if cached.bufnr and vim.api.nvim_buf_is_valid(cached.bufnr) then
          local result = vim.deepcopy(cached.result)
          local ctx = filter_context(result, {
            bufnr = cached.bufnr,
            client_id = client_id,
          })
          filter_result(result, ctx)
          vim.lsp.diagnostic.on_publish_diagnostics(nil, result, {
            bufnr = cached.bufnr,
            client_id = client_id,
          })
        else
          client_results[uri] = nil
        end
      end
    else
      cached_results[client_id] = nil
    end
  end
end

function M.toggle_inferred_mode(choice)
  if choice == nil then
    M.inferred_mode = M.inferred_mode == 'relaxed' and 'full' or 'relaxed'
  elseif choice == 'relaxed' or choice == 'full' then
    M.inferred_mode = choice
  else
    vim.notify(
      'TypeScript inferred diagnostics: invalid mode: ' .. tostring(choice),
      vim.log.levels.WARN
    )
    return
  end

  refresh_cached_results()
  vim.notify('Inferred JavaScript diagnostics: ' .. M.inferred_mode)
end

function M.dynamic_settings()
  return {
    diagnostics = {
      ignoredCodes = M.unused_diagnostics_ignored and M.unused_diagnostic_codes
        or {},
    },
  }
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

function M.toggle_unused(choice)
  if choice ~= nil then
    M.unused_diagnostics_ignored = choice == false
  else
    M.unused_diagnostics_ignored = not M.unused_diagnostics_ignored
  end

  local settings = M.dynamic_settings()
  pcall(vim.lsp.config, 'ts_ls', { settings = settings })

  for _, client in ipairs(vim.lsp.get_clients({ name = 'ts_ls' })) do
    client.config.settings =
      vim.tbl_deep_extend('force', client.config.settings or {}, settings)
    client:notify('workspace/didChangeConfiguration', {
      settings = client.config.settings,
    })

    if M.unused_diagnostics_ignored then
      clear_visible_unused_diagnostics(client)
    end
  end

  if not M.unused_diagnostics_ignored then
    refresh_cached_results()
  end

  local status = M.unused_diagnostics_ignored and 'hidden' or 'visible'
  vim.notify('TypeScript unused diagnostics: ' .. status)
end

return M
