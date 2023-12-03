local ct = require('lpke.core.helpers').concat_tables

local js = require('lpke.snippets.js')
local ts = require('lpke.snippets.ts')
local jsx = require('lpke.snippets.jsx')
local tsx = require('lpke.snippets.tsx')

return {
  all = require('lpke.snippets.all'),
  lua = require('lpke.snippets.lua'),
  javascript = js,
  typescript = ct(js, ts),
  javascriptreact = ct(js, jsx),
  typescriptreact = ct(js, ts, jsx, tsx),
}
