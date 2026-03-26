-- this is for use in the `Lpke_cc_model` function (for shorthand args)
-- for the lualine short names and the model multipliers, see
-- `plugins/lualine.lua`
return {
  -- defaults (duplicates for specific versions below)
  ['son'] = 'claude-sonnet-4.6',
  ['opus'] = 'claude-opus-4.6',
  ['gpt'] = 'gpt-5-mini', -- unlimited
  ['haiku'] = 'claude-haiku-4.5',
  ['gem'] = 'gemini-2.5-pro',
  ['grok'] = 'grok-code-fast-1',

  -- others, if running `Lpke_cc_model` manually
  ['opus4.6'] = 'claude-opus-4.6',
  ['opus4.5'] = 'claude-opus-4.5',
  ['son4.6'] = 'claude-sonnet-4.6',
  ['son4.5'] = 'claude-sonnet-4.5',
  ['son4'] = 'claude-sonnet-4',
  ['haiku4.5'] = 'claude-haiku-4.5',
  ['gpt5.2'] = 'gpt-5.2',
  ['gpt5.1'] = 'gpt-5.1',
  ['gpt5.1cM'] = 'gpt-5.1-codex-max',
  ['gpt5.1c'] = 'gpt-5.1-codex',
  ['gpt5m'] = 'gpt-5-mini', -- unlimited
  ['gpt4.1'] = 'gpt-4.1', -- unlimited
  ['gpt4o'] = 'gpt-4o', -- unlimited
  ['gem2.5'] = 'gemini-2.5-pro',
  ['grok1'] = 'grok-code-fast-1',
}
