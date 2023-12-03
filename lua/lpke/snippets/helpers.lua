local ls = require('luasnip')
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node
local fmt = require('luasnip.extras.fmt').fmt
local fmta = require('luasnip.extras.fmt').fmta
local rep = require('luasnip.extras').rep

-- simple one-line snippet: use `$0` to denote cursor end pos
local function snip(params, str, opts)
  local nodes = {}
  local startMatch, endMatch = string.find(str, '%$0')
  if startMatch then
    local before = string.sub(str, 1, startMatch - 1)
    local after = string.sub(str, endMatch + 1)
    table.insert(nodes, t(before))
    table.insert(nodes, i(1))
    table.insert(nodes, t(after))
  else
    table.insert(nodes, t(str))
  end

  return s(params, nodes, opts)
end

-- insets an empty new line
local function t_()
  return t({ '', '' })
end

return {
  snip = snip,
  -- require('luasnip')
  ls = ls,
  -- require('luasnip').snippet
  s = s,
  -- require('luasnip').snippet_node
  sn = sn,
  -- require('luasnip').text_node
  t = t,
  t_ = t_,
  -- require('luasnip').inset_node
  i = i,
  -- require('luasnip').function_node
  f = f,
  -- require('luasnip').dynamic_node
  d = d,
  -- require('luasnip.extras.fmt').fmt
  fmt = fmt,
  -- require('luasnip.extras.fmt').fmta
  fmeta = fmta,
  -- require('luasnip.extras').rep
  rep = rep,
}
