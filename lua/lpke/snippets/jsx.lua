-- stylua: ignore start
local h = require('lpke.snippets.ls_helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

local snippets = { -- jsreact
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
            <<div>>
              <<p>><><</p>>
            <</div>>
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
    fmtc(
      [[
        useEffect(() => {{
          {}
        }}, [{}]);
      ]],
      { i(1), i(2) }
    )
  ),
  _s(
    {
      trig = 'ued',
      name = 'useEffect debug',
    },
    fmtc(
      [[
        useEffect(() => {{
          console.log({{ {} }});
        }}, [{}]);
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
}

return require('lpke.core.helpers').concat_arrs(
  snippets,
  require('lpke.snippets.tailwind').jsx()
)
