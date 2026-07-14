-- stylua: ignore start
local h = require('lpke.snippets.ls_helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

local symbol_snippets = {}
local symbols = {
  { ':close:', '🗙' },
  { ':copyright:', '©' },
  { ':check:', '✔' },
  { ':cross:', '✖' },
  { ':star:', '★' },
  { ':arrow-up:', '↑' },
  { ':arrow-down:', '↓' },
  { ':arrow-left:', '←' },
  { ':arrow-right:', '→' },
  { ':sun:', '☀' },
  { ':moon:', '☾' },
  { ':ballot-checked:', '☑' },
  { ':ballot-crossed:', '☒' },
  { ':ballot-empty:', '☐' },
  { ':warning:', '⚠' },
  { ':bullet:', '•' },
  { ':ellipsis:', '…' },
  { ':degree:', '°' },
  { ':ellipsis-vertical:', '⋮' },
  { ':hamburger:', '☰' },
  { ':refresh:', '↻' },
  { ':settings:', '⚙' },
  { ':triangle-right:', '▶' },
  { ':triangle-down:', '▼' },
  { ':chevron-down:', '⌄' },
  { ':chevron-right:', '›' },
}

for _, symbol in ipairs(symbols) do
  table.insert(symbol_snippets, s(symbol[1], t(symbol[2])))
end

return require('lpke.core.helpers').concat_arrs(symbol_snippets, { -- all
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
})
