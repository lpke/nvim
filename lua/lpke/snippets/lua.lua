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
  }, fmta('Lpke_print(<>)', { i(0) })),
  s(']]', fmt('[[<>]]', { d(1, sel_b) })),
  s('test2', t('hello'), { condition = exp_conds.line_begin }),
}
