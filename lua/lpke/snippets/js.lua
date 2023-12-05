-- stylua: ignore start
local h = require('lpke.snippets.helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

return { -- js
  _s(
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
    )
  ),
  _s(
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
    )
  ),
  _s(
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
    )
  ),
  _s(
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
    )
  ),
  _s(
    {
      trig = 'fori',
      name = 'Numeric for loop',
    },
    fmt(
      [[
        for (let i = <>; i << <>; i<>) {
          <>
        }
      ]],
      { i(1, '0'), i(2, '.length'), i(3, '++'), i(4) }
    )
  ),
  _s(
    {
      trig = 'forof',
      name = 'Iterable for loop',
    },
    fmt(
      [[
        for (let <> of <><>) {
          <>
        }
      ]],
      { i(1, '[k, v]'), i(2, 'Object.entries()'), i(3), i(4) }
    )
  ),
  _s(
    {
      trig = 'forin',
      name = 'Iterable for loop',
    },
    fmt(
      [[
        for (let <> in <>) {
          <>
        }
      ]],
      { i(1, 'key'), i(2), i(3) }
    )
  ),
  s({
    trig = 'cl',
    name = 'Console Log',
  }, fmt('console.log(<>)', { i(1) })),
  s({
    trig = 'cld',
    name = 'Console Log Debug',
  }, fmt('console.log({ <> })', { i(1) })),
  _s({
    trig = '/cl',
    name = 'Console Log',
    snippetType = 'autosnippet',
  }, fmt('console.log(<>)', { i(1) })),
  _s(
    {
      trig = '/**',
      name = 'JSDoc comment',
    },
    fmt(
      [[
        /**
         * <>
         */
      ]],
      { i(1) }
    )
  ),
}
