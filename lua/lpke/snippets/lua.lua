local h = require('lpke.snippets.helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, sn, t, t_, i, f, d, fmt, fmta, rep =
  h.ls, h.s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.fmt, h.fmta, h.rep

return {
  s({
    trig = 'cl',
    name = '"Console Log"',
    dscr = 'Print using Lpke_print',
  }, fmta('Lpke_print(<>)', { i(0) })),
}
