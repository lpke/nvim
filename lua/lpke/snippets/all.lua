-- stylua: ignore start
local h = require('lpke.snippets.ls_helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

return { -- all
  _s(
    {
      trig = '```([%w%._+-]+)',
      name = 'Fenced code block',
      regTrig = true,
      wordTrig = false,
    },
    fmt(
      [[
```<>
<>
```
]],
      {
        f(function(_, snip)
          return snip.captures[1] or ''
        end, {}),
        d(1, sel),
      }
    )
  ),
  _s(
    {
      trig = '```',
      name = 'Fenced code block',
      wordTrig = false,
    },
    fmt(
      [[
```
<>
```
]],
      {
        d(1, sel),
      }
    )
  ),
  s({
    trig = '{}',
    name = 'Inline object',
  }, fmt('{ <> }', { i(1) })),
  s({
    trig = '[]',
    name = 'Inline array',
  }, fmt('[ <> ]', { i(1) })),
}
