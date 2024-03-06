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
      trig = 'rfc',
      name = 'React function component',
    },
    fmt(
      [[
        export <> function <>(<>) {
          return (
            <<div>><><</div>>
          );
        }
      ]],
      { i(1, 'default'), i(2), i(3, '{}'), rep(2) }
    )
  ),
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
  }, fmt('className="<>"', { i(1) })),
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

  -- material UI (MUI)
  s({
    trig = 'sx',
    name = 'MUI sx prop',
  }, fmt('sx={{ <> }}', { i(1) })),
  s({
    trig = '<Box',
    name = 'MUI Box component',
  }, fmt('<<Box sx={{ <> }}>><><</Box>>', { i(1), i(2) })),

  -- tailwind-style CSS convenience
  s({
    trig = 'flex',
    name = 'flex tailwind to CSS obj',
  }, fmt([[display: 'flex'<>]], { i(1) })),
  s({
    trig = 'flex;',
    name = 'flex tailwind to CSS',
  }, fmt('display: flex;<>', { i(1) })),
  s({
    trig = 'flex-row',
    name = 'flex-row tailwind to CSS obj',
  }, fmt([[flexDirection: 'row'<>]], { i(1) })),
  s({
    trig = 'flex-row;',
    name = 'flex-row tailwind to CSS',
  }, fmt('flex-direction: row;<>', { i(1) })),
  s({
    trig = 'flex-col',
    name = 'flex-col tailwind to CSS obj',
  }, fmt([[flexDirection: 'column'<>]], { i(1) })),
  s({
    trig = 'flex-col;',
    name = 'flex-col tailwind to CSS',
  }, fmt('flex-direction: column;<>', { i(1) })),
  s({
    trig = 'justify-start',
    name = 'justify-start tailwind to CSS obj',
  }, fmt([[justifyContent: 'flex-start'<>]], { i(1) })),
  s({
    trig = 'justify-start;',
    name = 'justify-start tailwind to CSS',
  }, fmt('justify-content: flex-start;<>', { i(1) })),
  s({
    trig = 'justify-end',
    name = 'justify-end tailwind to CSS obj',
  }, fmt([[justifyContent: 'flex-end'<>]], { i(1) })),
  s({
    trig = 'justify-end;',
    name = 'justify-end tailwind to CSS',
  }, fmt('justify-content: flex-end;<>', { i(1) })),
  s({
    trig = 'justify-center',
    name = 'justify-center tailwind to CSS obj',
  }, fmt([[justifyContent: 'center'<>]], { i(1) })),
  s({
    trig = 'justify-center;',
    name = 'justify-center tailwind to CSS',
  }, fmt('justify-content: center;<>', { i(1) })),
  s({
    trig = 'justify-between',
    name = 'justify-between tailwind to CSS obj',
  }, fmt([[justifyContent: 'space-between'<>]], { i(1) })),
  s({
    trig = 'justify-between;',
    name = 'justify-between tailwind to CSS',
  }, fmt('justify-content: space-between;<>', { i(1) })),
  s({
    trig = 'justify-around',
    name = 'justify-around tailwind to CSS obj',
  }, fmt([[justifyContent: 'space-around'<>]], { i(1) })),
  s({
    trig = 'justify-around;',
    name = 'justify-around tailwind to CSS',
  }, fmt('justify-content: space-around;<>', { i(1) })),
  s({
    trig = 'justify-evenly',
    name = 'justify-evenly tailwind to CSS obj',
  }, fmt([[justifyContent: 'space-evenly'<>]], { i(1) })),
  s({
    trig = 'justify-evenly;',
    name = 'justify-evenly tailwind to CSS',
  }, fmt('justify-content: space-evenly;<>', { i(1) })),
  s({
    trig = 'content-start',
    name = 'content-start tailwind to CSS obj',
  }, fmt([[alignContent: 'flex-start'<>]], { i(1) })),
  s({
    trig = 'content-start;',
    name = 'content-start tailwind to CSS',
  }, fmt('align-content: flex-start;<>', { i(1) })),
  s({
    trig = 'content-center',
    name = 'content-center tailwind to CSS obj',
  }, fmt([[alignContent: 'center'<>]], { i(1) })),
  s({
    trig = 'content-center;',
    name = 'content-center tailwind to CSS',
  }, fmt('align-content: center;<>', { i(1) })),
  s({
    trig = 'content-end',
    name = 'content-end tailwind to CSS obj',
  }, fmt([[alignContent: 'flex-end'<>]], { i(1) })),
  s({
    trig = 'content-end;',
    name = 'content-end tailwind to CSS',
  }, fmt('align-content: flex-end;<>', { i(1) })),
  s({
    trig = 'content-between',
    name = 'content-between tailwind to CSS obj',
  }, fmt([[alignContent: 'space-between'<>]], { i(1) })),
  s({
    trig = 'content-between;',
    name = 'content-between tailwind to CSS',
  }, fmt('align-content: space-between;<>', { i(1) })),
  s({
    trig = 'content-around',
    name = 'content-around tailwind to CSS obj',
  }, fmt([[alignContent: 'space-around'<>]], { i(1) })),
  s({
    trig = 'content-around;',
    name = 'content-around tailwind to CSS',
  }, fmt('align-content: space-around;<>', { i(1) })),
  s({
    trig = 'content-evenly',
    name = 'content-evenly tailwind to CSS obj',
  }, fmt([[alignContent: 'space-evenly'<>]], { i(1) })),
  s({
    trig = 'content-evenly;',
    name = 'content-evenly tailwind to CSS',
  }, fmt('align-content: space-evenly;<>', { i(1) })),
  s({
    trig = 'items-stretch',
    name = 'items-stretch tailwind to CSS obj',
  }, fmt([[alignItems: 'stretch'<>]], { i(1) })),
  s({
    trig = 'items-stretch;',
    name = 'items-stretch tailwind to CSS',
  }, fmt('align-items: stretch;<>', { i(1) })),
  s({
    trig = 'items-start',
    name = 'items-start tailwind to CSS obj',
  }, fmt([[alignItems: 'flex-start'<>]], { i(1) })),
  s({
    trig = 'items-start;',
    name = 'items-start tailwind to CSS',
  }, fmt('align-items: flex-start;<>', { i(1) })),
  s({
    trig = 'items-center',
    name = 'items-center tailwind to CSS obj',
  }, fmt([[alignItems: 'center'<>]], { i(1) })),
  s({
    trig = 'items-center;',
    name = 'items-center tailwind to CSS',
  }, fmt('align-items: center;<>', { i(1) })),
  s({
    trig = 'items-end',
    name = 'items-end tailwind to CSS obj',
  }, fmt([[alignItems: 'flex-end'<>]], { i(1) })),
  s({
    trig = 'items-end;',
    name = 'items-end tailwind to CSS',
  }, fmt('align-items: flex-end;<>', { i(1) })),
  s({
    trig = 'items-baseline',
    name = 'items-baseline tailwind to CSS obj',
  }, fmt([[alignItems: 'baseline'<>]], { i(1) })),
  s({
    trig = 'items-baseline;',
    name = 'items-baseline tailwind to CSS',
  }, fmt('align-items: baseline;<>', { i(1) })),
  s({
    trig = 'text-left',
    name = 'text-left tailwind to CSS obj',
  }, fmt([[textAlign: 'left'<>]], { i(1) })),
  s({
    trig = 'text-left;',
    name = 'text-left tailwind to CSS',
  }, fmt('text-align: left;<>', { i(1) })),
  s({
    trig = 'text-center',
    name = 'text-center tailwind to CSS obj',
  }, fmt([[textAlign: 'center'<>]], { i(1) })),
  s({
    trig = 'text-center;',
    name = 'text-center tailwind to CSS',
  }, fmt('text-align: center;<>', { i(1) })),
  s({
    trig = 'text-right',
    name = 'text-right tailwind to CSS obj',
  }, fmt([[textAlign: 'right'<>]], { i(1) })),
  s({
    trig = 'text-right;',
    name = 'text-right tailwind to CSS',
  }, fmt('text-align: right;<>', { i(1) })),
  s({
    trig = 'text-justify',
    name = 'text-justify tailwind to CSS obj',
  }, fmt([[textAlign: 'justify'<>]], { i(1) })),
  s({
    trig = 'text-justify;',
    name = 'text-justify tailwind to CSS',
  }, fmt('text-align: justify;<>', { i(1) })),
}
