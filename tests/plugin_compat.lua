vim.opt.rtp:prepend(vim.fn.getcwd())
local helper = require('lpke.core.helpers.plugin')
local validate = vim.validate
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local checks = 0
local function check(value, label)
  checks = checks + 1
  assert(value, label)
end
local function fails(callback, message)
  local ok, err = pcall(callback)
  check(not ok and tostring(err):find(message, 1, true), message)
end
local function run()
  for _, value in ipairs({
    { 'text', 's' },
    { 4, 'n' },
    { false, 'b' },
    { {}, 't' },
    { function() end, 'f' },
    { function() end, 'c' },
    { 'text', { 'n', 's' } },
    { nil, 'number', true },
    {
      4,
      function(number)
        return number > 0
      end,
      'positive',
    },
  }) do
    check(
      pcall(helper.validate_table, { value = value }),
      'supported validator'
    )
  end
  fails(function()
    helper.validate_table({ value = { 'bad', 'n' } })
  end, 'value: expected number, got string')
  fails(function()
    helper.validate_table({ value = { false, { 'n', 's' } } })
  end, 'value: expected number|string, got boolean')
  fails(function()
    helper.validate_table({
      value = {
        0,
        function()
          return false
        end,
        'positive',
      },
    })
  end, 'value: expected positive, got 0')
  fails(function()
    helper.validate_table({ bad = false })
  end, 'opt[bad]: expected table, got boolean')
  local visited = 0
  local predicate = function()
    visited = visited + 1
    return false
  end
  fails(function()
    helper.validate_table({ z = { 0, predicate }, a = { 0, predicate } })
  end, 'a: expected ?, got 0')
  check(visited == 2, 'all predicates execute before reporting first error')

  local path = root .. '/module.lua'
  local source = [[local M = {}
function M.run(value)
  vim.validate { value = { value, 'number' } }
  return value * 2
end
return M
]]
  local file = assert(io.open(path, 'wb'))
  file:write(source)
  file:close()
  local digest = vim.fn.sha256(source)
  helper.patch_validation('lpke_fixture.module', path, digest, 1)
  local preload = package.preload['lpke_fixture.module']
  helper.patch_validation('lpke_fixture.module', path, digest, 1)
  check(
    package.preload['lpke_fixture.module'] == preload,
    'registration is idempotent'
  )
  local module = require('lpke_fixture.module')
  check(module.run(3) == 6, 'original module behavior retained')
  fails(function()
    module.run('bad')
  end, 'expected number')
  check(
    require('lpke_fixture.module') == module,
    'normal require cache retained'
  )
  check(
    table.concat(vim.fn.readfile(path), '\n') .. '\n' == source,
    'plugin source remains unchanged'
  )

  helper.patch_validation('lpke_fixture.changed', path, 'bad digest', 1)
  fails(function()
    require('lpke_fixture.changed')
  end, 'Plugin source changed')
  helper.patch_validation('lpke_fixture.count', path, digest, 2)
  fails(function()
    require('lpke_fixture.count')
  end, 'validation sites changed')
  fails(function()
    helper.patch_validation('lpke.core.helpers.plugin', path, digest, 1)
  end, 'already loaded')
  package.preload['lpke_fixture.occupied'] = function()
    return {}
  end
  fails(function()
    helper.patch_validation('lpke_fixture.occupied', path, digest, 1)
  end, 'already registered')

  local loader = package.loaded['lazy.core.loader']
  local entered, compilations = false, 0
  package.loaded['lazy.core.loader'] = {
    auto_load = function(name)
      if not entered then
        entered = true
        require(name)
      end
    end,
  }
  helper.patch_module('lpke_fixture.reentrant', path, digest, function(code)
    compilations = compilations + 1
    return code
  end)
  local reentrant = require('lpke_fixture.reentrant')
  package.loaded['lazy.core.loader'] = loader
  check(entered and compilations == 1, 'reentrant Lazy autoload compiles once')
  check(
    reentrant == package.loaded['lpke_fixture.reentrant'],
    'autoload returns inner cached module'
  )
  check(
    vim.validate == validate,
    'native validation function remains unchanged'
  )
end
local ok, err = xpcall(run, debug.traceback)
vim.fn.delete(root, 'rf')
if not ok then
  error(err)
end
print(('PASS plugin compatibility: %d checks'):format(checks))
