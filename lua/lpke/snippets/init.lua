local ct = require('lpke.core.helpers').concat_arrs

local html = require('lpke.snippets.html')
local js = require('lpke.snippets.js')
local ts = require('lpke.snippets.ts')
local jsx = require('lpke.snippets.jsx')
local tsx = require('lpke.snippets.tsx')

return {
  all = require('lpke.snippets.all'),
  lua = require('lpke.snippets.lua'),
  html = html,
  javascript = js,
  typescript = ct(ts, js),
  javascriptreact = ct(jsx, js, html),
  typescriptreact = ct(tsx, jsx, ts, js, html),
}
