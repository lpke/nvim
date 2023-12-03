local ls = require('luasnip')
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node
local rep = require('luasnip.extras').rep -- repeat insert node (multi-cursor)

-- human-readable text node formatters using delimeters for insert nodes (used in place of a node table)
local fmt = require('luasnip.extras.fmt').fmt -- default delimeter: {}
local fmta = require('luasnip.extras.fmt').fmta -- default delimeter: <>

-- insets an empty new line
local function t_()
  return t({ '', '' })
end

return {
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
  fmta = fmta,
  -- require('luasnip.extras').rep
  rep = rep,
}
