---@class lpke.core.helpers: lpke.core.helpers.misc, lpke.core.helpers.util, lpke.core.helpers.config, lpke.core.helpers.print, lpke.core.helpers.info, lpke.core.helpers.format
local M = {}

local misc = require('lpke.core.helpers.misc')
local util = require('lpke.core.helpers.util')
local config = require('lpke.core.helpers.config')
local print = require('lpke.core.helpers.print')
local info = require('lpke.core.helpers.info')
local format = require('lpke.core.helpers.format')

-- make all available via `lpke.core.helpers.<function>`
for k, v in pairs(misc) do
  M[k] = v
end
for k, v in pairs(util) do
  M[k] = v
end
for k, v in pairs(config) do
  M[k] = v
end
for k, v in pairs(print) do
  M[k] = v
end
for k, v in pairs(info) do
  M[k] = v
end
for k, v in pairs(format) do
  M[k] = v
end

return M
