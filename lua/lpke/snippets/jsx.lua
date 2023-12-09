-- stylua: ignore start
local h = require('lpke.snippets.ls_helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

return { -- jsreact
  _s({
    trig = 'ii',
    name = 'Import',
  }, fmt("import <> from '<>';", { i(1, '{  }'), i(2) })),
  _s(
    {
      trig = 'ue',
      name = 'useEffect',
    },
    fmt(
      [[
        useEffect(() =>> {
          <>
        }, [<>]);
      ]],
      { i(1), i(2) }
    )
  ),
  _s(
    {
      trig = 'ued',
      name = 'useEffect debug',
    },
    fmt(
      [[
        useEffect(() =>> {
          console.log({ <> });
        }, [<>]);
      ]],
      { i(1), rep(1) }
    )
  ),
  _s(
    {
      trig = 'us',
      name = 'useState',
    },
    fmt(
      [[
        const [<>, set<>] = useState(<>);
      ]],
      {
        i(1),
        f(function(args)
          return (args[1][1]:gsub('^%l', string.upper))
        end, { 1 }),
        i(2),
      }
    )
  ),
  s({
    trig = 'cn',
    name = 'JSX className',
  }, fmt('className=')),
  s({
    trig = '}}',
    name = 'Template literal expression',
    dscr = 'Convert quoted text to a curly-brace wrapped template literal',
  }, fmt('{`<>`}', { d(1, sel_q) })),
  s({
    trig = '}}$',
    name = 'Temperate string interpolation',
  }, fmt('{`<> ${<>}`}', { d(2, sel_q), i(1) })),
  s({
    trig = '}&',
    name = 'Conditional expression',
  }, fmt('{<> && (<>)}', { i(1), i(2, '<div></div>') })),
  s({
    trig = '}?',
    name = 'Ternary expression',
  }, fmt('{<> ? <> : <>}', { i(1), i(2, '()'), i(3, '()') })),
}
