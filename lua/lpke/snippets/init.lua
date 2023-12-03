local ct = require('lpke.core.helpers').concat_tables

local js = require('lpke.snippets.js')
local ts = require('lpke.snippets.ts')
local jsreact = require('lpke.snippets.jsreact')
local tsreact = require('lpke.snippets.tsreact')

return {
  all = require('lpke.snippets.all'),
  lua = require('lpke.snippets.lua'),
  javascript = js,
  typescript = ct(js, ts),
  javascriptreact = ct(js, jsreact),
  typescriptreact = ct(js, ts, jsreact, tsreact),
}
