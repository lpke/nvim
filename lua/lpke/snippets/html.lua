-- stylua: ignore start
local h = require('lpke.snippets.ls_helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

return { -- html
  s({
    trig = 'did',
    name = 'Document Element by ID',
  }, fmt('document.getElementById(<>)', { i(1) })),
  s({
    trig = 'ds',
    name = 'Document Query Selector',
  }, fmt('document.querySelector(<>)', { i(1) })),
  s({
    trig = 'dsa',
    name = 'Document Query Selector All',
  }, fmt('document.querySelectorAll(<>)', { i(1) })),
  s({
    trig = 'cl',
    name = 'Console Log',
  }, fmt('console.log(<>)', { i(1) })),
  s({
    trig = 'cld',
    name = 'Console Log Debug',
  }, fmt('console.log({ <> })', { i(1) })),
}
