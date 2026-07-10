-- stylua: ignore start
local h = require('lpke.snippets.ls_helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

local ct = require('lpke.core.helpers').concat_arrs
local class_helpers = require('lpke.snippets.js_class_helpers')
local test_snippets = require('lpke.snippets.js_test')

local function postfix_s(params, nodes)
  params.wordTrig = false
  return s(params, nodes, {
    condition = h.before_trigger_matches('%S'),
  })
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
  _s({
    trig = 'pall',
    name = 'Promise.all',
  }, fmt('Promise.all([<>]);', { i(1) })),
  _s({
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
  _s({
    trig = 'pres',
    name = 'Promise.resolve',
  }, fmt('Promise.resolve(<>);', { i(1) })),
  _s({
    trig = 'prej',
    name = 'Promise.reject',
  }, fmt('Promise.reject(<>);', { i(1) })),
  _s({
    trig = 'prace',
    name = 'Promise.race',
  }, fmt('Promise.race([<>]);', { i(1) })),
  _s({
    trig = 'pany',
    name = 'Promise.any',
  }, fmt('Promise.any([<>]);', { i(1) })),
  _s(
    {
      trig = 'rf',
      name = 'Return arrow function',
    },
    fmt(
      [[
        return (<>) =>> {
          <>
        };
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
    trig = '.ce',
    name = 'Create element suffix',
  }, { t("document.createElement('"), i(1), t("')") }),
  postfix_s({
    trig = '.ac',
    name = 'appendChild suffix',
  }, { t('.appendChild('), i(1), t(')') }),
  postfix_s({
    trig = '.rc',
    name = 'removeChild suffix',
  }, { t('.removeChild('), i(1), t(')') }),
  postfix_s({
    trig = '.cl',
    name = 'classList suffix',
  }, t('.classList')),
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
