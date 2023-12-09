-- stylua: ignore start
local h = require('lpke.snippets.ls_helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

return { -- lua
  _s(
    {
      trig = 'snipps',
      name = 'Luasnip single line snippet',
    },
    fmt(
      [[
        <>s({
          trig = '<>',
          name = '<>',
        }, fmt('<>', { i(1)<> })<>),
      ]],
      { i(1, '_'), i(2), i(3), i(4), i(5), i(6) }
    )
  ),
  _s(
    {
      trig = 'snippm',
      name = 'Luasnip multiline snippet',
    },
    fmt(
      [==[
        <>s(
          {
            trig = '<>',
            name = '<>',
          },
          fmt(
            [[
              <> 
            ]],
            { i(1)<> }
          )<>
        ),
      ]==],
      { i(1, '_'), i(2), i(3), i(4), i(5), i(6) }
    )
  ),
  _s(
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
    )
  ),
  _s(
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
        if <> then
          <>
        end
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
        if <> then
          <>
        else
          <>
        end
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
        for i = 1, <> do
          <>
        end
      ]],
      { i(1), i(2) }
    )
  ),
  _s(
    {
      trig = 'forp',
      name = 'Table iteration for loop',
    },
    fmt(
      [[
        for k, v in <>pairs(<>) do
          <>
        end
      ]],
      { i(1, 'i'), i(2), i(3) }
    )
  ),
  s({
    trig = 'cl',
    name = '"Console Log"',
  }, fmt('print(<>)', { i(1) })),
  _s({
    trig = '/cl',
    name = '"Console Log"',
    snippetType = 'autosnippet',
  }, fmt('print(<>)', { i(1) })),
  s({
    trig = 'cll',
    name = 'Lpke "Console Log"',
  }, fmt('Lpke_print(<>)', { i(1) })),
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
