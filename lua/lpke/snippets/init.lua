local ct = require('lpke.core.helpers').concat_tables

local js = require('lpke.snippets.js')
local ts = require('lpke.snippets.ts')

return {
  all = require('lpke.snippets.all'),
  lua = require('lpke.snippets.lua'),
  javascript = js,
  typescript = ct(js, ts),
}
