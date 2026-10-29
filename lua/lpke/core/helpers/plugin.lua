local M = {}
local registered = {}
local aliases = {
  b = 'boolean',
  c = 'callable',
  f = 'function',
  n = 'number',
  s = 'string',
  t = 'table',
}

local function normalize(validator)
  if type(validator) == 'string' then
    return aliases[validator] or validator
  end
  if type(validator) == 'table' and not vim.is_callable(validator) then
    return vim.tbl_map(function(value)
      return aliases[value] or value
    end, validator)
  end
  return validator
end

-- Translate these pinned plugins' validation specifications into the current
-- API. Evaluate every validator and report the first error alphabetically,
-- matching the legacy contract without calling Neovim's deprecated overload.
function M.validate_table(spec)
  vim.validate('spec', spec, 'table')
  local errors = {}
  for name, check in pairs(spec) do
    if type(check) ~= 'table' then
      errors[name] = ('opt[%s]: expected table, got %s'):format(
        name,
        type(check)
      )
    elseif not (check[1] == nil and check[3] == true) then
      if check[2] == nil then
        errors[name] = 'invalid validator: nil'
      else
        local ok, err =
          pcall(vim.validate, name, check[1], normalize(check[2]), check[3])
        if not ok then
          errors[name] = tostring(err):gsub('^.-:%d+:%s*', '', 1)
        end
      end
    end
  end
  for _, err in vim.spairs(errors) do
    error(err, 2)
  end
end

-- Adapt a specific pinned module in memory. Checkouts stay untouched and its
-- original functions, closures and caches remain together in one Lua chunk.
function M.patch_module(name, path, digest, transform)
  if registered[name] then
    return
  end
  assert(not package.loaded[name], 'Plugin module already loaded: ' .. name)
  assert(
    not package.preload[name],
    'Plugin module already registered: ' .. name
  )
  registered[name] = true
  package.preload[name] = function(...)
    -- Match Lazy's own loader: mount dependencies first and permit after/plugin
    -- to require this module while the outer autoload is still in progress.
    package.loaded[name] = nil
    local loader = package.loaded['lazy.core.loader']
    if loader then
      loader.auto_load(name, path)
      if type(package.loaded[name]) == 'table' then
        return package.loaded[name]
      end
    end
    local file = assert(io.open(path, 'rb'))
    local source = file:read('*a')
    file:close()
    assert(
      vim.fn.sha256(source) == digest,
      'Plugin source changed; review its compatibility patch: ' .. name
    )
    local chunk = assert(loadstring(transform(source), '@' .. path))
    return chunk(...)
  end
end

function M.patch_validation(name, path, digest, expected)
  M.patch_module(name, path, digest, function(source)
    local patched, count = source:gsub('vim%.validate', 'lpke_validate_table')
    assert(count == expected, 'Plugin validation sites changed: ' .. name)
    return "local lpke_validate_table = require('lpke.core.helpers.plugin').validate_table; "
      .. patched
  end)
end

return M
