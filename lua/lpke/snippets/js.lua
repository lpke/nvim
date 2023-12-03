-- stylua: ignore start
local h = require('lpke.snippets.helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

return {
  s(
    {
      trig = 'ff',
      name = 'Function',
    },
    fmt(
      [[
        function <>(<>) {
          <>
        }
      ]],
      { i(1), i(2), i(3) }
    ),
    { condition = exp_conds.line_begin }
  ),
  s(
    {
      trig = 'if',
      name = 'If statement',
    },
    fmt(
      [[
        if (<>) {
          <>
        }
      ]],
      { i(1), i(2) }
    ),
    { condition = exp_conds.line_begin }
  ),
  s(
    {
      trig = '/if',
      name = 'If statement',
      snippetType = 'autosnippet',
    },
    fmt(
      [[
        if (<>) {
          <>
        }
      ]],
      { i(1), i(2) }
    ),
    { condition = exp_conds.line_begin }
  ),
  s(
    {
      trig = 'ifel',
      name = 'If Else statement',
    },
    fmt(
      [[
        if (<>) {
          <>
        } else {
          <>
        }
      ]],
      { i(1), i(2), i(3) }
    ),
    { condition = exp_conds.line_begin }
  ),
  s({
    trig = 'cl',
    name = 'Console Log',
  }, fmt('console.log(<>)', { i(1) })),
  s({
    trig = 'cld',
    name = 'Console Log Debug',
  }, fmt('console.log({ <> })', { i(1) })),
  s({
    trig = '/cl',
    name = 'Console Log',
    snippetType = 'autosnippet',
  }, fmt('console.log(<>)', { i(1) }), { condition = exp_conds.line_begin }),
}
