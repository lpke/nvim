-- Exercise native lualine callback storage after scoped validation adaptation.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.loadplugins = true
local warnings = {}
local deprecate = vim.deprecate
vim.deprecate = function(name, ...)
  warnings[#warnings + 1] = name
  return deprecate(name, ...)
end
dofile('init.lua')

local checks = 0
local function check(value, label)
  checks = checks + 1
  assert(value, label)
end
local store = require('lualine.utils.fn_store')
local id = 999999
local callback = function(...)
  return select('#', ...), ...
end
check(
  store.register_fn(id, callback) == id,
  'registration returns component ID'
)
check(store.get_fn(id) == callback, 'registered callback identity')
local count, first, second, third = store.call_fn(id, 'text', nil, 42)
check(
  count == 3 and first == 'text' and second == nil and third == 42,
  'callback arguments and multiple returns preserve nils'
)
check(store.call_fn(id + 1) == nil, 'missing component is a safe no-op')
check(
  not pcall(store.register_fn, 'bad', callback),
  'invalid component rejected'
)
check(not pcall(store.register_fn, id, 'bad'), 'invalid callback rejected')
check(not pcall(store.get_fn, 'bad'), 'invalid lookup rejected')
check(
  store.get_fn(id) == callback,
  'invalid registration preserves existing callback'
)
local replacement = function()
  return 'replacement'
end
store.register_fn(id, replacement)
check(
  store.call_fn(id) == 'replacement',
  'registration replaces same component'
)
check(
  type(require('lualine').statusline(true)) == 'string',
  'actual statusline renders'
)
store.clear_fns()
check(store.call_fn(id) == nil, 'clear removes registered callbacks')
check(
  #warnings == 0,
  'startup and callback store use no deprecated APIs: ' .. vim.inspect(warnings)
)
vim.deprecate = deprecate
print(('PASS lualine callbacks: %d checks'):format(checks))
