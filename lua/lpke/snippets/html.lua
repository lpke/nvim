-- stylua: ignore start
local h = require('lpke.snippets.ls_helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_dedent, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_dedent, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

local function sel_or(default)
  return function(_args, parent)
    local selection = parent.snippet.env.LS_SELECT_DEDENT
    if #selection > 0 then
      return sn(nil, i(1, selection))
    end
    return sn(nil, i(1, default))
  end
end

return { -- html
  s({
    trig = 'cn',
    name = 'HTML class attribute',
  }, fmt('class="<>"', { i(1) })),
  s(
    {
      trig = 'form',
      name = 'HTML form',
    },
    fmt(
      [[<<form>>
  <>
<</form>>
]],
      {
        d(1, sel_dedent),
      }
    )
  ),
  s(
    {
      trig = 'input',
      name = 'HTML input',
    },
    fmt('<<input id="<>" name="<>" type="<>" autocomplete="<>" />>', {
      d(1, sel_or('')),
      d(2, sel_or('')),
      i(3, 'text'),
      i(4),
    })
  ),
  s(
    {
      trig = 'label',
      name = 'HTML label',
    },
    fmt('<<label for="<>">><><</label>>', {
      i(1),
      d(2, sel_or('')),
    })
  ),
  s(
    {
      trig = 'img',
      name = 'HTML image',
    },
    fmt('<<img src="<>" alt="<>" />>', {
      i(1),
      d(2, sel),
    })
  ),
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
  }, fmt('console.log(<>);', { i(1) })),
  s({
    trig = 'cld',
    name = 'Console Log Debug',
  }, fmt('console.log({ <> });', { i(1) })),
  s({
    trig = 'ce',
    name = 'Console Error',
  }, fmt('console.error(<>);', { i(1) })),
  s({
    trig = 'ced',
    name = 'Console Error Debug',
  }, fmt('console.error({ <> });', { i(1) })),
}
