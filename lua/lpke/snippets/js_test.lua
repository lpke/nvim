-- stylua: ignore start
local h = require('lpke.snippets.ls_helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

local cond_obj = require('luasnip.extras.conditions')

local test_file_condition = cond_obj.make_condition(function()
  return vim.api.nvim_buf_get_name(0):match('%.test%.[jt]s$') ~= nil
end)

local function test_s(params, nodes)
  return _s(params, nodes, {
    condition = exp_conds.line_begin * test_file_condition,
  })
end

local function test_suffix_s(params, nodes)
  params.wordTrig = false
  return h.s_allow_hyphen(params, nodes, {
    condition = h.before_trigger_matches('%S') * test_file_condition,
  })
end

return {
  test_s(
    {
      trig = 'vii',
      name = 'Vitest import',
    },
    t(
      "import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';"
    )
  ),
  test_s({
    trig = 'vis',
    name = 'Vitest scaffold',
  }, {
    t({ "import { describe, it, expect } from 'vitest';", '', "describe('" }),
    i(1),
    t({ "', () => {", "  it('" }),
    i(2),
    t({ "', () => {", '    ' }),
    i(3),
    t({ '', '  });', '});' }),
  }),
  test_s({
    trig = 'd',
    name = 'Vitest describe',
  }, { t("describe('"), i(1), t("', () => {"), i(2), t('});') }),
  test_s({
    trig = 'i',
    name = 'Vitest it',
  }, { t("it('"), i(1), t("', () => {"), i(2), t('});') }),
  test_s({
    trig = 'ia',
    name = 'Vitest async it',
  }, { t("it('"), i(1), t("', async () => {"), i(2), t('});') }),
  test_s(
    {
      trig = 'ie',
      name = 'Vitest it.each named cases',
    },
    fmtc(
      [[
        it.each([
          {{ input: {}, expected: {} }},
          {{ input: {}, expected: {} }},
        ])('{}', ({{ input, expected }}) => {{
          {}
        }});
      ]],
      {
        i(1),
        i(2),
        i(3),
        i(4),
        i(5, '$input -> $expected'),
        i(6, 'expect(isEven(input)).toBe(expected);'),
      }
    )
  ),
  test_s({
    trig = 'be',
    name = 'Vitest beforeEach',
  }, { t('beforeEach(() => {'), i(1), t('});') }),
  test_s({
    trig = 'ae',
    name = 'Vitest afterEach',
  }, { t('afterEach(() => {'), i(1), t('});') }),
  test_s({
    trig = 'e',
    name = 'Vitest expect',
  }, fmt('expect(<>).<>', { i(1), i(2) })),
  test_suffix_s({
    trig = '.tb',
    name = 'Vitest toBe suffix',
  }, fmt('.toBe(<>);', { i(1) })),
  test_suffix_s({
    trig = '.te',
    name = 'Vitest toEqual suffix',
  }, fmt('.toEqual(<>);', { i(1) })),
  test_s({
    trig = 'etb',
    name = 'Vitest expect toBe',
  }, fmt('expect(<>).toBe(<>);', { d(1, sel), i(2) })),
  test_s({
    trig = 'ete',
    name = 'Vitest expect toEqual',
  }, fmt('expect(<>).toEqual(<>);', { d(1, sel), i(2) })),
  test_s({
    trig = 'etm',
    name = 'Vitest expect toMatchObject',
  }, fmt('expect(<>).toMatchObject(<>);', { d(1, sel), i(2) })),
  test_s({
    trig = 'ehp',
    name = 'Vitest expect toHaveProperty',
  }, fmt("expect(<>).toHaveProperty('<>', <>);", { d(1, sel), i(2), i(3) })),
  test_s({
    trig = 'ehl',
    name = 'Vitest expect toHaveLength',
  }, fmt('expect(<>).toHaveLength(<>);', { d(1, sel), i(2) })),
  test_s({
    trig = 'etc',
    name = 'Vitest expect toContain',
  }, fmt('expect(<>).toContain(<>);', { d(1, sel), i(2) })),
  test_s({
    trig = 'eth',
    name = 'Vitest expect toThrow',
  }, fmtc('expect(() => {}).toThrow({});', { d(1, sel), i(2) })),
  test_s({
    trig = 'ertb',
    name = 'Vitest expect resolves toBe',
  }, fmt('expect(<>).resolves.toBe(<>);', { i(1), i(2) })),
  test_s({
    trig = 'erte',
    name = 'Vitest expect resolves toEqual',
  }, fmt('expect(<>).resolves.toEqual(<>);', { i(1), i(2) })),
  test_s({
    trig = 'erth',
    name = 'Vitest expect rejects toThrow',
  }, fmt('expect(<>).rejects.toThrow(<>);', { i(1), i(2) })),
  test_s({
    trig = 'ecn',
    name = 'Vitest expect called times',
  }, fmt('expect(<>).toHaveBeenCalledTimes(<>);', { i(1), i(2) })),
  test_s({
    trig = 'ecw',
    name = 'Vitest expect called with',
  }, fmt('expect(<>).toHaveBeenCalledWith(<>);', { i(1), i(2) })),
  test_s({
    trig = 'eco',
    name = 'Vitest expect called once',
  }, fmt('expect(<>).toHaveBeenCalledOnce();', { i(1) })),
  test_s({
    trig = 'vfn',
    name = 'Vitest vi.fn',
  }, fmt('const <> = vi.fn();', { i(1, 'fn') })),
  test_s({
    trig = 'vfr',
    name = 'Vitest vi.fn mockReturnValue',
  }, fmt('const <> = vi.fn().mockReturnValue(<>);', { i(1, 'fn'), i(2) })),
  test_s({
    trig = 'vfa',
    name = 'Vitest vi.fn mockResolvedValue',
  }, fmt('const <> = vi.fn().mockResolvedValue(<>);', { i(1, 'fn'), i(2) })),
  test_s(
    {
      trig = 'vmo',
      name = 'Vitest vi.mock module',
    },
    fmtc(
      [[
        vi.mock('{}', () => ({{
          {}: vi.fn().mockResolvedValue({}),
        }}));
      ]],
      { i(1, './api'), i(2, 'fetchUser'), i(3, '{}') }
    )
  ),
  test_s(
    {
      trig = 'vsp',
      name = 'Vitest spyOn',
    },
    fmtc(
      [[
        const {} = vi.spyOn({}, '{}').mockImplementation(() => {{}});
        {}
      ]],
      { i(1, 'spy'), i(2, 'console'), i(3, 'log'), i(4) }
    )
  ),
  test_s({
    trig = 'vcm',
    name = 'Vitest clearAllMocks',
  }, t('vi.clearAllMocks();')),
  test_s({
    trig = 'vrm',
    name = 'Vitest restoreAllMocks',
  }, t('vi.restoreAllMocks();')),
  test_s(
    {
      trig = 'vti',
      name = 'Vitest fake timers',
    },
    fmt(
      [[
        vi.useFakeTimers();
        <>
        vi.useRealTimers();
      ]],
      { i(1) }
    )
  ),
}
