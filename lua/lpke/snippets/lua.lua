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
        local function <>(<>)
          <>
        end
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
        if <> then
          <>
        end
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
        if <> then
          <>
        end
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
        if <> then
          <>
        else
          <>
        end
      ]],
      { i(1), i(2), i(3) }
    ),
    { condition = exp_conds.line_begin }
  ),
  s({
    trig = 'cl',
    name = '"Console Log"',
  }, fmt('Lpke_print(<>)', { i(1) })),
  s({
    trig = '/cl',
    name = '"Console Log"',
    snippetType = 'autosnippet',
  }, fmt('Lpke_print(<>)', { i(1) }), { condition = exp_conds.line_begin }),
  s({
    trig = ']]',
    name = 'Convert to [[]]',
    dscr = 'Replace quotes surrounding selection with multiline string syntax',
  }, fmt('[[<>]]', { d(1, sel_q) })),
  s({
    trig = 'q]]',
    name = 'Wrap with [[]]',
    dscr = 'Wrap selection with [[]], preserving surroudning quotes',
  }, fmt('[[<>]]', { d(1, sel) })),
}
