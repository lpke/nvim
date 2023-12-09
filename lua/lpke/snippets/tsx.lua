-- stylua: ignore start
local h = require('lpke.snippets.ls_helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

return { -- tsreact
  _s(
    {
      trig = 'rfc',
      name = 'React function component',
    },
    fmt(
      [[
        type <>Props = {<>};
        
        export <> function <>(<>) {
          return (
            <<div>><><</div>>
          );
        }
      ]],
      { rep(2), i(4), i(1, 'default'), i(2), i(3, '{}'), rep(2) }
    )
  ),
  _s(
    {
      trig = 'rfcc',
      name = 'React function component (arrow)',
    },
    fmt(
      [[
        type <>Props = {<>};
        
        const <> = (<>) =>> {
          return (
            <<div>><><</div>>
          );
        };

        export default <>;
      ]],
      { rep(1), i(3), i(1), i(2, '{}'), rep(1), rep(1) }
    )
  ),
}
