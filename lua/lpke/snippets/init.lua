local ct = require('lpke.core.helpers').concat_arrs

-- filetype-specific snippets
local html = require('lpke.snippets.html')
local css = require('lpke.snippets.css')
local js = require('lpke.snippets.js')
local ts = require('lpke.snippets.ts')
local jsx = require('lpke.snippets.jsx')
local tsx = require('lpke.snippets.tsx')
local vue = require('lpke.snippets.vue')

-- js/ts snippet inheritance
local jsSnippets = js
local jsxSnippets = ct(jsx, js, html)
local tsSnippets = ct(ts, js)
local tsxSnippets = ct(tsx, jsx, ts, js, html)
local vueSnippets = ct(vue, ts, js)

return {
  all = require('lpke.snippets.all'),
  lua = require('lpke.snippets.lua'),
  html = html,
  css = css,
  js = jsSnippets,
  javascript = jsSnippets,
  ts = tsSnippets,
  typescript = tsSnippets,
  jsx = jsxSnippets,
  javascriptreact = jsxSnippets,
  tsx = tsxSnippets,
  typescriptreact = tsxSnippets,
  vue = vueSnippets,
}
