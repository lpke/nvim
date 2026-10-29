-- Offline checks using upstream's defaults application and installed ACP names.
-- nvim --headless -u NONE -i NONE -l tests/codecompanion_codex_mode.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
for _, plugin in ipairs({ 'codecompanion.nvim', 'plenary.nvim' }) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end
require('codecompanion').setup({})
local defaults = require('codecompanion.interactions.chat.acp.defaults')
local mode = require('lpke.plugins.ai.helpers.codex_mode')
mode.setup()
local patched = defaults.apply
mode.setup()
assert(defaults.apply == patched, 'Setup must be idempotent')

local checks, warnings = 0, {}
vim.notify = function(message)
  if message:find('Codex ACP has no matching Full Access mode', 1, true) then
    warnings[#warnings + 1] = message
  end
end
local function eq(actual, expected, label)
  checks = checks + 1
  assert(vim.deep_equal(actual, expected), label .. ': ' .. vim.inspect(actual))
end
local function apply(values, requested, opts)
  opts = opts or {}
  local option = {
    id = 'mode',
    category = 'mode',
    type = 'select',
    currentValue = 'agent',
    options = values,
  }
  local model = {
    id = 'model',
    category = 'model',
    type = 'select',
    currentValue = 'old',
    options = { { value = 'new', name = 'New' } },
  }
  local adapter = {
    name = opts.adapter or 'codex',
    defaults = { session_config_options = { mode = requested, model = 'new' } },
  }
  local original = vim.deepcopy(adapter)
  local calls = {}
  defaults.apply(adapter, {
    get_config_options = function()
      return { option, model }
    end,
    set_config_option = function(_, id, value)
      calls[#calls + 1] = { id, value }
      if id == 'model' and opts.after_model then
        option.options = opts.after_model
      end
      if id == 'mode' then
        option.currentValue = value
      end
    end,
  })
  eq(calls[1], { 'model', 'new' }, 'Model set first')
  eq(adapter, original, 'Shared adapter defaults unchanged')
  return option.currentValue, calls
end

for _, label in ipairs({ 'Agent (full access)', 'Full access' }) do
  for _, requested in ipairs({
    'agent-full-access',
    'Full Access',
    'Agent (full access)',
  }) do
    eq(
      apply({ { value = 'agent-full-access', name = label } }, requested),
      'agent-full-access',
      'Old and new display names with either configured name'
    )
  end
end
for _, id in ipairs({ 'full-access', 'full_access', 'danger-full-access' }) do
  eq(
    apply({ { value = id, name = 'Renamed mode' } }, 'agent-full-access'),
    id,
    'Recognized ID alias'
  )
end
for _, label in ipairs({ 'Full Access', 'Agent (full access)', 'FULL_ACCESS' }) do
  eq(
    apply({ { value = 'future-id', name = label } }, 'agent-full-access'),
    'future-id',
    'Changed ID resolved by advertised name'
  )
end
eq(
  apply({
    {
      group = 'permissions',
      name = 'Permissions',
      options = {
        { value = 'new-grouped-id', name = 'Full Access' },
      },
    },
  }, 'Full Access'),
  'new-grouped-id',
  'Grouped advertised values'
)
eq(
  apply({
    {
      value = 'future-kind-id',
      name = 'Unrestricted',
      _meta = { jetbrains = { air = { kind = 'full_access' } } },
    },
  }, 'agent-full-access'),
  'future-kind-id',
  'Explicit full_access metadata'
)
eq(
  apply({
    { value = 'label-match', name = 'Full Access' },
    { value = 'agent-full-access', name = 'New label' },
  }, 'Full Access'),
  'agent-full-access',
  'Stable ID preferred over display label'
)
eq(
  apply({ { value = 'read-only', name = 'Read-only' } }, 'read-only'),
  'read-only',
  'Explicit restricted mode preserved'
)
eq(
  apply(
    { { value = 'full-access', name = 'Full Access' } },
    'agent-full-access',
    { adapter = 'other' }
  ),
  'agent',
  'Other adapters unchanged'
)
eq(
  apply({}, 'agent-full-access', {
    after_model = {
      { value = 'model-specific-id', name = 'Full Access' },
    },
  }),
  'model-specific-id',
  'Resolution uses options after model change'
)
eq(
  apply({ { value = 'agent-full-access', name = 'Full access' } }, function()
    return 'Full Access'
  end),
  'agent-full-access',
  'Callable default'
)
eq(#warnings, 0, 'Supported modes need no warning')
local current, calls = apply({
  { value = 'agent', name = 'Auto review' },
  { value = 'workspace-write', name = 'Full auto' },
}, 'agent-full-access')
eq(current, 'agent', 'Unrecognized modes never guessed')
eq(#calls, 1, 'No unsupported mode ID sent')
eq(#warnings, 1, 'Missing full access produces visible warning')

-- Read only the installed mode declaration. Never start an ACP agent or model.
local package_root = vim.fn.expand(
  '~/.local/share/npm/lib/node_modules/@agentclientprotocol/codex-acp'
)
local source =
  table.concat(vim.fn.readfile(package_root .. '/dist/index.js'), '\n')
local id, label = source:match(
  'static AgentFullAccess = new _AgentMode%(%s*"([^"]+)",%s*"([^"]+)"'
)
assert(id and label, 'Installed ACP full access declaration not found')
eq(
  apply({ { value = id, name = label } }, 'agent-full-access'),
  id,
  'Installed ACP mode accepted by upstream defaults'
)
local version = vim.json.decode(
  table.concat(vim.fn.readfile(package_root .. '/package.json'), '\n')
).version
print(
  ('PASS: %d Codex mode checks; installed ACP %s: %s / %s'):format(
    checks,
    version,
    id,
    label
  )
)
vim.cmd('qa!')
