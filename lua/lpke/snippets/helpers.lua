local ls = require('luasnip')
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node
local rep = require('luasnip.extras').rep -- repeat insert node (multi-cursor)
local fmtc = require('luasnip.extras.fmt').fmt -- default delimeter: {} (curly)
local fmta = require('luasnip.extras.fmt').fmta -- default delimeter: <> (angled)
local exp_conds = require('luasnip.extras.expand_conditions')

-- use with a `d(1, sel)` node to a `fmt` to fill insert with selection
-- (selection is set with <Tab> in visual mode)
local sel = function(_, parent) -- (args, parent)
  if #parent.snippet.env.LS_SELECT_RAW > 0 then
    return sn(nil, i(1, parent.snippet.env.LS_SELECT_RAW))
  else -- If LS_SELECT_RAW is empty, return a blank insert node
    return sn(nil, i(1))
  end
end

-- `sel`, but removes surrounding quotes from the selection
local sel_q = function(_, parent)
  local q_regex = '["\'`]'
  local selection = parent.snippet.env.LS_SELECT_RAW
  if #selection > 0 then
    selection[1] =
      selection[1]:gsub('^' .. q_regex, ''):gsub(q_regex .. '$', '')
    return sn(nil, i(1, selection))
  else -- If LS_SELECT_RAW is empty, return a blank insert node
    return sn(nil, i(1))
  end
end

-- `sel`, but removes surrounding brackets from the selection
local sel_b = function(_, parent)
  local b_regex_open = '[\\(\\[\\{\\<]'
  local b_regex_close = '[\\)\\]\\}\\>]'
  local selection = parent.snippet.env.LS_SELECT_RAW
  if #selection > 0 then
    selection[1] =
      selection[1]:gsub('^' .. b_regex_open, ''):gsub(b_regex_close .. '$', '')
    return sn(nil, i(1, selection))
  else -- If LS_SELECT_RAW is empty, return a blank insert node
    return sn(nil, i(1))
  end
end

-- text node helper for creating an empty new line
local function t_()
  return t({ '', '' })
end

-- same as luasnip `fmta` but no optional second arg
local function fmt(str, nodes, opts)
  nodes = nodes or {}
  return fmta(str, nodes, opts)
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
  -- require('luasnip.extras').rep
  rep = rep,
  -- require('luasnip.extras.fmt').fmt
  fmtc = fmtc,
  -- require('luasnip.extras.fmt').fmta
  fmta = fmta,
  -- require('luasnip.extras.fmt').fmta (optional second arg)
  fmt = fmt,
  sel = sel,
  sel_q = sel_q,
  sel_b = sel_b,
  -- presets passable to `condition = ...` in last arg of `s()`
  exp_conds = exp_conds,
}
