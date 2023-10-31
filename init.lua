---@diagnostic disable-next-line: deprecated
table.unpack = table.unpack or unpack -- Lua 5.1 compatibility

require('lpke.core') -- vim config/keymaps
require('lpke.lazy') -- handles `lpke.plugins`
