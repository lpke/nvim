-- stylua: ignore start
local h = require('lpke.snippets.ls_helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_dedent, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_dedent, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

local ct = require('lpke.core.helpers').concat_arrs
local class_helpers = require('lpke.snippets.js_class_helpers')
local test_snippets = require('lpke.snippets.js_test')

local function postfix_s(params, nodes)
  params.wordTrig = false
  return h.s_allow_hyphen(params, nodes, {
    condition = h.before_trigger_matches('%S'),
  })
end

local function event_listener_suffix(trig, event, editable)
  local event_node = editable and i(1, event) or t(event)
  local body_node = i(editable and 2 or 1)

  return postfix_s(
    {
      trig = trig,
      name = event .. ' event listener suffix',
    },
    fmtc(
      [[
      .addEventListener('{}', (e) => {{
        {}
      }});
    ]],
      { event_node, body_node }
    )
  )
end

local function array_callback_suffix(trig, method)
  return postfix_s({
    trig = trig,
    name = method .. ' suffix',
  }, fmtc('.' .. method .. '(({}) => {})', { i(1, 'item'), i(2) }))
end

return ct(test_snippets, { -- js
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
  _s({
    trig = 'con',
    name = 'Constructor',
  }, d(1, class_helpers.constructor)),
  _s({
    trig = 'conf',
    name = 'Constructor with fields',
  }, d(1, class_helpers.constructor_with_fields)),
  s({
    trig = 'pall',
    name = 'Promise.all',
  }, fmt('Promise.all([<>]);', { i(1) })),
  s({
    trig = 'palls',
    name = 'Promise.allSettled',
  }, fmt('Promise.allSettled([<>]);', { i(1) })),
  _s(
    {
      trig = 'pwr',
      name = 'Promise.withResolvers',
    },
    fmt(
      'const { promise, resolve, reject } = Promise.withResolvers<>();',
      { i(1) }
    )
  ),
  s({
    trig = 'pres',
    name = 'Promise.resolve',
  }, fmt('Promise.resolve(<>);', { i(1) })),
  s({
    trig = 'prej',
    name = 'Promise.reject',
  }, fmt('Promise.reject(<>);', { i(1) })),
  s({
    trig = 'prace',
    name = 'Promise.race',
  }, fmt('Promise.race([<>]);', { i(1) })),
  s({
    trig = 'pany',
    name = 'Promise.any',
  }, fmt('Promise.any([<>]);', { i(1) })),
  s(
    {
      trig = 'st',
      name = 'setTimeout',
    },
    fmtc(
      [[
        setTimeout(() => {{
          {}
        }}, {});
      ]],
      { i(1), i(2, '0') }
    )
  ),
  s(
    {
      trig = 'si',
      name = 'setInterval',
    },
    fmtc(
      [[
        setInterval(() => {{
          {}
        }}, {});
      ]],
      { i(1), i(2, '1000') }
    )
  ),
  _s(
    {
      trig = 'rf',
      name = 'Return arrow function',
    },
    fmtc(
      [[
        return ({}) => {{
          {}
        }};
      ]],
      { i(1), i(2) }
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
      trig = 'switch',
      name = 'Switch statement',
    },
    fmt(
      [[
        switch (<>) {
          <>
        }
      ]],
      { i(1), i(2) }
    )
  ),
  _s(
    {
      trig = 'c',
      name = 'Switch case',
      priority = 1100,
    },
    fmt(
      [[
        case '<>':
          <>
          break;
      ]],
      { i(1), i(2) }
    ),
    { condition = h.has_ts_ancestor('switch_statement') }
  ),
  _s(
    {
      trig = 'd',
      name = 'Switch default',
      priority = 1100,
    },
    fmt(
      [[
        default:
          <>
      ]],
      { i(1) }
    ),
    { condition = h.has_ts_ancestor('switch_statement') }
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
      trig = 'tc',
      name = 'Try Catch',
    },
    fmt(
      [[
        try {
          <>
        } catch (<>) {
          <>
        }
      ]],
      { d(1, sel), i(2, 'err'), i(3) }
    )
  ),
  _s(
    {
      trig = 'tcf',
      name = 'Try Catch Finally',
    },
    fmt(
      [[
        try {
          <>
        } catch (<>) {
          <>
        } finally {
          <>
        }
      ]],
      { d(1, sel), i(2, 'err'), i(3), i(4) }
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
      trig = 'fo',
      name = 'Indexed iterable for loop',
    },
    fmt(
      [[
        for (const [index, <>] of <>.entries()) {
          <>
        }
      ]],
      { i(1), i(2), i(3) }
    )
  ),
  _s(
    {
      trig = 'forof',
      name = 'Iterable for loop',
    },
    fmt(
      [[
        for (const <> of <><>) {
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
        for (const <> in <>) {
          <>
        }
      ]],
      { i(1, 'key'), i(2), i(3) }
    )
  ),
  s({
    trig = 'cl',
    name = 'Console Log',
  }, fmt('console.log(<>);', { d(1, sel_dedent) })),
  s({
    trig = 'cld',
    name = 'Console Log Debug',
  }, fmt('console.log({ <> });', { i(1) })),
  s({
    trig = 'ce',
    name = 'Console Error',
  }, fmt('console.error(<>);', { d(1, sel_dedent) })),
  s({
    trig = 'ced',
    name = 'Console Error Debug',
  }, fmt('console.error({ <> });', { i(1) })),
  s({
    trig = 'did',
    name = 'Document Element by ID',
  }, { t("document.getElementById('"), i(1), t("')") }),
  s({
    trig = 'ds',
    name = 'Document Query Selector',
  }, { t("document.querySelector('"), i(1), t("')") }),
  s({
    trig = 'dsa',
    name = 'Document Query Selector All',
  }, { t("document.querySelectorAll('"), i(1), t("')") }),
  s({
    trig = 'dce',
    name = 'Document Create Element',
  }, { t("document.createElement('"), i(1), t("')") }),
  postfix_s(
    {
      trig = '.fe',
      name = 'forEach suffix',
    },
    fmtc(
      [[
      .forEach(({}) => {{
        {}
      }});
    ]],
      { i(1, 'item'), i(2) }
    )
  ),
  array_callback_suffix('.map', 'map'),
  array_callback_suffix('.filter', 'filter'),
  postfix_s(
    {
      trig = '.reduce',
      name = 'reduce suffix',
    },
    fmtc(
      '.reduce(({}, {}) => {}, {})',
      { i(1, 'acc'), i(2, 'item'), i(3), i(4, 'initialValue') }
    )
  ),
  array_callback_suffix('.find', 'find'),
  array_callback_suffix('.findIndex', 'findIndex'),
  array_callback_suffix('.some', 'some'),
  array_callback_suffix('.every', 'every'),
  array_callback_suffix('.fm', 'flatMap'),
  postfix_s({
    trig = '.id',
    name = 'getElementById suffix',
  }, { t(".getElementById('"), i(1), t("')") }),
  postfix_s({
    trig = '.qs',
    name = 'querySelector suffix',
  }, { t(".querySelector('"), i(1), t("')") }),
  postfix_s({
    trig = '.qsa',
    name = 'querySelectorAll suffix',
  }, { t(".querySelectorAll('"), i(1), t("')") }),
  postfix_s({
    trig = '.ac',
    name = 'appendChild suffix',
  }, { t('.appendChild('), i(1), t(');') }),
  postfix_s({
    trig = '.rc',
    name = 'removeChild suffix',
  }, { t('.removeChild('), i(1), t(');') }),
  postfix_s({
    trig = '.ap',
    name = 'append suffix',
  }, { t('.append('), i(1), t(');') }),
  postfix_s({
    trig = '.pp',
    name = 'prepend suffix',
  }, { t('.prepend('), i(1), t(');') }),
  postfix_s({
    trig = '.bf',
    name = 'before suffix',
  }, { t('.before('), i(1), t(');') }),
  postfix_s({
    trig = '.af',
    name = 'after suffix',
  }, { t('.after('), i(1), t(');') }),
  postfix_s({
    trig = '.rw',
    name = 'replaceWith suffix',
  }, { t('.replaceWith('), i(1), t(');') }),
  postfix_s({
    trig = '.rch',
    name = 'replaceChildren suffix',
  }, { t('.replaceChildren('), i(1), t(');') }),
  postfix_s({
    trig = '.rm',
    name = 'remove suffix',
  }, t('.remove();')),
  postfix_s({
    trig = '.cl',
    name = 'classList suffix',
  }, t('.classList')),
  postfix_s({
    trig = '.cla',
    name = 'classList add suffix',
  }, { t(".classList.add('"), i(1), t("');") }),
  postfix_s({
    trig = '.clr',
    name = 'classList remove suffix',
  }, { t(".classList.remove('"), i(1), t("');") }),
  postfix_s({
    trig = '.clt',
    name = 'classList toggle suffix',
  }, { t(".classList.toggle('"), i(1), t("');") }),
  postfix_s({
    trig = '.ga',
    name = 'getAttribute suffix',
  }, { t(".getAttribute('"), i(1), t("')") }),
  postfix_s({
    trig = '.sa',
    name = 'setAttribute suffix',
  }, { t(".setAttribute('"), i(1), t("', '"), i(2), t("');") }),
  postfix_s({
    trig = '.ra',
    name = 'removeAttribute suffix',
  }, { t(".removeAttribute('"), i(1), t("');") }),
  postfix_s({
    trig = '.ta',
    name = 'toggleAttribute suffix',
  }, { t(".toggleAttribute('"), i(1), t("');") }),
  postfix_s({
    trig = '.tc',
    name = 'textContent assignment suffix',
  }, { t('.textContent = '), i(1), t(';') }),
  postfix_s({
    trig = '.pd',
    name = 'preventDefault suffix',
  }, t('.preventDefault();')),
  postfix_s({
    trig = '.sp',
    name = 'stopPropagation suffix',
  }, t('.stopPropagation();')),
  postfix_s({
    trig = '.sip',
    name = 'stopImmediatePropagation suffix',
  }, t('.stopImmediatePropagation();')),
  event_listener_suffix('.ael', 'click', true),
  event_listener_suffix('.aelc', 'click'),
  postfix_s(
    {
      trig = '.aeli',
      name = 'input event listener suffix',
    },
    fmtc(
      [[
      .addEventListener('input', (e) => {{
        if (e instanceof InputEvent && e.target instanceof HTMLInputElement) {{
          {}
        }}
      }});
    ]],
      { i(1, '// text input handling') }
    )
  ),
  event_listener_suffix('.aelm', 'mousemove'),
  event_listener_suffix('.aelr', 'resize'),
  event_listener_suffix('.aels', 'submit'),
  event_listener_suffix('.aelkd', 'keydown'),
  event_listener_suffix('.aelku', 'keyup'),
  event_listener_suffix('.aelf', 'focus'),
  event_listener_suffix('.aelb', 'blur'),
  event_listener_suffix('.aeld', 'drag'),
  event_listener_suffix('.aelds', 'dragstart'),
  event_listener_suffix('.aelde', 'dragend'),
  _s({
    trig = '/cl',
    name = 'Console Log',
    snippetType = 'autosnippet',
  }, fmt('console.log(<>);', { i(1) })),
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
})
