vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/cmp-nvim-lsp')
local checks, deprecations = 0, {}
local function check(value, label)
  checks = checks + 1
  assert(value, label)
end
local deprecate = vim.deprecate
vim.deprecate = function(name, ...)
  deprecations[#deprecations + 1] = name
  return deprecate(name, ...)
end

local requests, notifications, sequence, closed = {}, {}, 0, false
local transport = {
  request = function(method, params, callback)
    sequence = sequence + 1
    if method == 'initialize' then
      vim.schedule(function()
        callback(nil, {
          capabilities = {
            completionProvider = { resolveProvider = true },
            executeCommandProvider = { commands = { 'fixture.execute' } },
            textDocumentSync = { openClose = true, change = 2 },
          },
        })
      end)
    else
      requests[#requests + 1] =
        { id = sequence, method = method, params = params, callback = callback }
    end
    return true, sequence
  end,
  notify = function(method, params)
    notifications[#notifications + 1] = { method = method, params = params }
    return true
  end,
  is_closing = function()
    return closed
  end,
  terminate = function()
    closed = true
  end,
}
local client_id = vim.lsp.start({
  name = 'lpke-completion-methods',
  cmd = function()
    return transport
  end,
})
local client = assert(vim.lsp.get_client_by_id(client_id))
check(
  vim.wait(1000, function()
    return client.initialized
  end),
  'native LSP initializes'
)
local source = require('cmp_nvim_lsp.source').new(client)
check(
  source:is_available(),
  'native client is attached and completion is available'
)

local completions = {}
local params = { option = {}, completion_context = { triggerKind = 1 } }
source:complete(params, function(result)
  completions[#completions + 1] = result
end)
source:complete(params, function(result)
  completions[#completions + 1] = result
end)
check(#requests == 2, 'two completion requests reach the real client transport')
check(
  requests[1].method == 'textDocument/completion',
  'completion method preserved'
)
local cancellation
for _, event in ipairs(notifications) do
  if event.method == '$/cancelRequest' then
    cancellation = event.params.id
  end
end
check(cancellation == requests[1].id, 'superseded completion is cancelled')
requests[1].callback(nil, { items = { { label = 'stale' } } })
requests[2].callback(nil, { items = { { label = 'current' } } })
check(
  vim.wait(1000, function()
    return #completions == 1
  end),
  'only current completion callback runs'
)
check(completions[1].items[1].label == 'current', 'newest completion survives')

local resolved
source:resolve({ label = 'current' }, function(result)
  resolved = result
end)
local resolve = requests[#requests]
check(
  resolve.method == 'completionItem/resolve',
  'resolve reaches native client'
)
resolve.callback(nil, { label = 'current', detail = 'resolved documentation' })
check(
  vim.wait(1000, function()
    return resolved ~= nil
  end),
  'resolve callback runs'
)
check(
  resolved.detail == 'resolved documentation',
  'resolved documentation retained'
)

local executed = false
source:execute(
  { command = { command = 'fixture.execute', arguments = { 'value' } } },
  function()
    executed = true
  end
)
local execute = requests[#requests]
check(
  execute.method == 'workspace/executeCommand'
    and execute.params.arguments[1] == 'value',
  'completion command reaches native client'
)
execute.callback(nil, nil)
check(
  vim.wait(1000, function()
    return executed
  end),
  'execute callback runs'
)
client:stop(true)
check(not source:is_available(), 'stopped native client disables completion')
check(
  #deprecations == 0,
  'native client methods never use deprecated dot wrappers'
)
vim.deprecate = deprecate
print(('PASS LSP completion methods: %d checks'):format(checks))
