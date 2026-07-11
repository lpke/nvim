local ls = require('luasnip')
local luasnip_s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node
local rep = require('luasnip.extras').rep -- repeat insert node (multi-cursor)
local cond_obj = require('luasnip.extras.conditions')
local fmtc = require('luasnip.extras.fmt').fmt -- default delimeter: {} (curly)
local fmta = require('luasnip.extras.fmt').fmta -- default delimeter: <> (angled)
local exp_conds = require('luasnip.extras.expand_conditions')
local helpers = require('lpke.core.helpers')

local no_hyphen_boundary = exp_conds.trigger_not_preceded_by('[%w_-]')

-- `s()` with `-` treated as part of a word. Use `s_allow_hyphen()` to opt out.
local function s(params, nodes, opts)
  if type(params) == 'string' then
    params = { trig = params }
  end

  params = helpers.merge_tables(params, { wordTrig = false })
  opts = opts or {}
  opts = helpers.merge_tables(opts, {
    condition = opts.condition and no_hyphen_boundary * opts.condition
      or no_hyphen_boundary,
  })

  return luasnip_s(params, nodes, opts)
end

local function s_allow_hyphen(params, nodes, opts)
  return luasnip_s(params, nodes, opts)
end

-- `s()` that adds `{ condition = exp_conds.line_begin }` by default
local function _s(params, nodes, opts)
  nodes = nodes or {}
  opts = opts or {}
  opts = helpers.merge_tables({ condition = exp_conds.line_begin }, opts)
  return s(params, nodes, opts)
end

-- `t()` that creates a new line
local function t_()
  return t({ '', '' })
end

-- `fmta()` with optional second arg
local function fmt(str, nodes, opts)
  nodes = nodes or {}
  return fmta(str, nodes, opts)
end

local function before_trigger_matches(pattern)
  pattern = pattern or '%S'
  return cond_obj.make_condition(function(line_to_cursor, matched_trigger)
    local before_trigger = line_to_cursor:sub(1, -(#matched_trigger + 1))
    return before_trigger:match(pattern) ~= nil
  end)
end

local function selected_lines(parent, kind)
  kind = kind or 'raw'

  local env = parent and parent.snippet and parent.snippet.env
  local selection = env
    and env[kind == 'dedent' and 'LS_SELECT_DEDENT' or 'LS_SELECT_RAW']

  if type(selection) == 'table' and #selection > 0 then
    return selection
  end

  return nil
end

local function selected_text(parent, kind, join)
  local selection = selected_lines(parent, kind)

  if selection then
    return table.concat(selection, join or '\n')
  end

  return nil
end

-- use with a `d(1, sel)` node to a `fmt` to fill insert with selection
-- (selection is set with <Tab> in visual mode)
local sel = function(_args, parent)
  return sn(nil, i(1, selected_lines(parent) or ''))
end

-- `sel`, but uses LuaSnip's common-indent-stripped selection.
local sel_dedent = function(_args, parent)
  return sn(nil, i(1, selected_lines(parent, 'dedent') or ''))
end

-- `sel`, but removes surrounding quotes from the selection
local sel_q = function(_args, parent)
  local q_regex = '["\'`]'
  local selection = selected_lines(parent)

  if selection then
    selection = vim.list_extend({}, selection)
    selection[1] =
      selection[1]:gsub('^' .. q_regex, ''):gsub(q_regex .. '$', '')
  end

  return sn(nil, i(1, selection or ''))
end

-- `sel`, but removes surrounding brackets from the selection
local sel_b = function(_args, parent)
  local b_regex_open = '[%(%[%{%<]'
  local b_regex_close = '[%)%]%}%>]'
  local selection = selected_lines(parent)

  if selection then
    selection = vim.list_extend({}, selection)
    selection[1] =
      selection[1]:gsub('^' .. b_regex_open, ''):gsub(b_regex_close .. '$', '')
  end

  return sn(nil, i(1, selection or ''))
end

local function sel_or(default, kind)
  return function(_args, parent)
    return sn(nil, i(1, selected_lines(parent, kind) or default))
  end
end

return {
  -- require('luasnip')
  ls = ls,
  -- require('luasnip').snippet
  s = s,
  -- require('luasnip').snippet with LuaSnip's default hyphen boundary
  s_allow_hyphen = s_allow_hyphen,
  _s = _s,
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
  selected_text = selected_text,
  sel = sel,
  sel_or = sel_or,
  sel_dedent = sel_dedent,
  sel_q = sel_q,
  sel_b = sel_b,
  -- presets passable to `condition = ...` in last arg of `s()`
  exp_conds = exp_conds,
  before_trigger_matches = before_trigger_matches,
}
