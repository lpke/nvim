-- stylua: ignore start
local h = require('lpke.snippets.helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

return {
  s({
    trig = 'cl',
    name = '"Console Log"',
    dscr = 'Print using Lpke_print',
  }, fmt('Lpke_print(<>)', { i(0) })),
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
