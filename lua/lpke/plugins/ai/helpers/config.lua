local M = {}

M.adapters = {
  copilot = {
    display = 'Copilot',
    default_model = 'sonnet',
    model_cycle = { 'sonnet', 'gpt' },
  },
  codex = {
    display = 'Codex',
    default_model = 'gpt_5_5',
    model_cycle = { 'gpt_5_5', 'gpt_5_3_codex_spark' },
  },
}
M.adapter_cycle = { 'codex', 'copilot' }

M.defaults = {
  chat_adapter = 'codex',
  inline_adapter = 'copilot',
  cmd_adapter = 'copilot',
  title_generation_adapter = 'copilot',
  title_generation_model = 'gpt',
}

M.preferred_models = {
  opus = 'opus_4_7',
  son = 'sonnet_4_6',
  sonnet = 'sonnet_4_6',
  haiku = 'haiku_4_5',
  gpt = 'gpt_5_mini',
  gem = 'gemini_3_1_pro',
  gemini = 'gemini_3_1_pro',
  grok = 'grok_code_fast_1',
}

-- Note: Copilot-specific display names include premium request multipliers as at 29/04/2026.
-- https://docs.github.com/en/copilot/concepts/billing/copilot-requests
M.models = {
  opus_4_7 = {
    id = 'claude-opus-4.7',
    aliases = { 'opus4.7' },
    display = 'opus-4.7',
    adapter_display = { copilot = 'opus-4.7 (x7.5)' },
  },
  opus_4_6 = {
    id = 'claude-opus-4.6',
    aliases = { 'opus4.6' },
    display = 'opus-4.6',
    adapter_display = { copilot = 'opus-4.6 (x3)' },
  },
  opus_4_5 = {
    id = 'claude-opus-4.5',
    aliases = { 'opus4.5' },
    display = 'opus-4.5',
    adapter_display = { copilot = 'opus-4.5 (x3)' },
  },
  sonnet_4_6 = {
    id = 'claude-sonnet-4.6',
    aliases = { 'son4.6' },
    display = 'sonnet-4.6',
    adapter_display = { copilot = 'sonnet-4.6 (x1)' },
  },
  sonnet_4_5 = {
    id = 'claude-sonnet-4.5',
    aliases = { 'son4.5' },
    display = 'sonnet-4.5',
    adapter_display = { copilot = 'sonnet-4.5 (x1)' },
  },
  sonnet_4 = {
    id = 'claude-sonnet-4',
    aliases = { 'son4' },
    display = 'sonnet-4',
    adapter_display = { copilot = 'sonnet-4 (x1)' },
  },
  haiku_4_5 = {
    id = 'claude-haiku-4.5',
    aliases = { 'haiku4.5' },
    display = 'haiku-4.5',
    adapter_display = { copilot = 'haiku-4.5 (x0.33)' },
  },
  gpt_5_5 = {
    id = 'gpt-5.5',
    aliases = { 'gpt5.5' },
    display = 'GPT-5.5',
    adapter_display = { copilot = 'GPT-5.5 (x7.5)' },
  },
  gpt_5_4 = {
    id = 'gpt-5.4',
    aliases = { 'gpt5.4' },
    display = 'GPT-5.4',
  },
  gpt_5_4_mini = {
    id = 'gpt-5.4-mini',
    aliases = { 'gpt5.4m' },
    display = 'GPT-5.4m',
  },
  gpt_5_3_codex = {
    id = 'gpt-5.3-codex',
    aliases = { 'gpt5.3c' },
    display = 'GPT-5.3c',
  },
  gpt_5_3_codex_spark = {
    id = 'gpt-5.3-codex-spark',
    aliases = { 'gpt5.3cs' },
    display = 'GPT-5.3cs',
  },
  gpt_5_2_codex = {
    id = 'gpt-5.2-codex',
    aliases = { 'gpt5.2c' },
    display = 'GPT-5.2c',
  },
  gpt_5_2 = {
    id = 'gpt-5.2',
    aliases = { 'gpt5.2' },
    display = 'GPT-5.2',
    adapter_display = { copilot = 'GPT-5.2 (x1)' },
  },
  gpt_5_1 = {
    id = 'gpt-5.1',
    aliases = { 'gpt5.1' },
    display = 'GPT-5.1',
    adapter_display = { copilot = 'GPT-5.1 (x1)' },
  },
  gpt_5_1_codex_max = {
    id = 'gpt-5.1-codex-max',
    aliases = { 'gpt5.1cM' },
    display = 'GPT-5.1cM',
    adapter_display = { copilot = 'GPT-5.1cM (x1)' },
  },
  gpt_5_1_codex = {
    id = 'gpt-5.1-codex',
    aliases = { 'gpt5.1c' },
    display = 'GPT-5.1c',
    adapter_display = { copilot = 'GPT-5.1c (x1)' },
  },
  gpt_5_mini = {
    id = 'gpt-5-mini',
    aliases = { 'gpt5m' },
    display = 'GPT-5m',
    adapter_display = { copilot = 'GPT-5m (∞)' },
  },
  gpt_4_1 = {
    id = 'gpt-4.1',
    aliases = { 'gpt4.1' },
    display = 'GPT-4.1',
    adapter_display = { copilot = 'GPT-4.1 (∞)' },
  },
  gpt_4o = {
    id = 'gpt-4o',
    aliases = { 'gpt4o' },
    display = 'GPT-4o',
    adapter_display = { copilot = 'GPT-4o (∞)' },
  },
  gemini_3_1_pro = {
    id = 'gemini-3.1-pro-preview',
    aliases = { 'gem3.1' },
    display = 'gemini-3.1p',
    adapter_display = { copilot = 'gemini-3.1p (x1)' },
  },
  gemini_3_flash = {
    id = 'gemini-3-flash-preview',
    aliases = { 'gem3' },
    display = 'gemini-3f',
    adapter_display = { copilot = 'gemini-3f (x0.33)' },
  },
  gemini_2_5_pro = {
    id = 'gemini-2.5-pro',
    aliases = { 'gem2.5' },
    display = 'gemini-2.5p',
    adapter_display = { copilot = 'gemini-2.5p (x1)' },
  },
  grok_code_fast_1 = {
    id = 'grok-code-fast-1',
    aliases = { 'grok1' },
    display = 'grok-fast-1',
    adapter_display = { copilot = 'grok-fast-1 (x0.25)' },
  },
}

local model_lookup = {}

local function build_model_lookup()
  for alias, key in pairs(M.preferred_models) do
    model_lookup[alias] = M.models[key]
  end

  for key, model in pairs(M.models) do
    model_lookup[key] = model
    model_lookup[model.id] = model

    for _, alias in ipairs(model.aliases or {}) do
      model_lookup[alias] = model
    end
  end
end

build_model_lookup()

function M.model_id(model)
  if not model then
    return nil
  end

  local entry = model_lookup[model]
  return entry and entry.id or model
end

function M.adapter_default_model(adapter)
  local adapter_config = M.adapters[adapter] or {}
  return M.model_id(adapter_config.default_model)
end

function M.adapter_display_name(adapter)
  local adapter_config = M.adapters[adapter] or {}
  return adapter_config.display or adapter
end

function M.adapter_model_cycle(adapter)
  local adapter_config = M.adapters[adapter] or {}
  local cycle = {}

  for i, model in ipairs(adapter_config.model_cycle or {}) do
    cycle[i] = M.model_id(model)
  end

  return cycle
end

function M.lualine_model_name(model, adapter)
  local entry = model_lookup[model]
  if not entry then
    return model
  end

  local adapter_display = entry.adapter_display or {}
  return adapter_display[adapter] or entry.display or entry.id
end

return M
