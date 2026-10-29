-- Run with: run-nvim --headless -u NONE -l tests/nvim_0_12_pyright_deprecations.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/nvim-lspconfig')
local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local deprecations = {}
local deprecate = vim.deprecate
vim.deprecate = function(name, ...)
  deprecations[#deprecations + 1] = debug.traceback(name, 2)
  return deprecate(name, ...)
end

local calls, notifications = {}, {}
local client = {
  config = {
    settings = { python = { analysis = { useLibraryCodeForTypes = true } } },
  },
}
function client:request(method, params, handler, bufnr)
  check(self == client, 'request uses the client method receiver')
  calls[#calls + 1] =
    { method = method, params = params, handler = handler, bufnr = bufnr }
end
function client:notify(method, params)
  check(self == client, 'notification uses the client method receiver')
  notifications[#notifications + 1] = { method = method, params = params }
end
local bufnr = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '.py')
require('lpke.lsp.pyright').on_attach(client, bufnr)
local commands = vim.api.nvim_buf_get_commands(bufnr, {})
check(
  commands.LspPyrightOrganizeImports ~= nil,
  'organize imports command retained'
)
check(commands.LspPyrightSetPythonPath ~= nil, 'Python path command retained')
check(
  commands.LspPyrightSetPythonPath.nargs == '1',
  'Python path argument retained'
)
check(
  commands.LspPyrightSetPythonPath.complete == 'file',
  'Python path completion retained'
)
vim.cmd.LspPyrightOrganizeImports()
check(
  #calls == 1 and calls[1].method == 'workspace/executeCommand',
  'execute command request'
)
check(
  calls[1].params.command == 'pyright.organizeimports',
  'private Pyright command retained'
)
check(
  calls[1].params.arguments[1] == vim.uri_from_bufnr(bufnr),
  'document URI passed'
)
check(
  calls[1].handler == nil and calls[1].bufnr == bufnr,
  'request handler and buffer retained'
)

local get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function(filter)
  check(
    filter.bufnr == bufnr and filter.name == 'pyright',
    'Python path client filter'
  )
  return { client }
end
vim.cmd.LspPyrightSetPythonPath('/tmp/python-config-fixture')
check(
  client.config.settings.python.pythonPath == '/tmp/python-config-fixture',
  'Python path changed'
)
check(
  client.config.settings.python.analysis.useLibraryCodeForTypes,
  'Python analysis settings retained'
)
client.settings =
  { python = { analysis = { diagnosticMode = 'openFilesOnly' } } }
vim.cmd.LspPyrightSetPythonPath('/tmp/python-client-fixture')
check(
  client.settings.python.pythonPath == '/tmp/python-client-fixture',
  'client Python settings changed'
)
check(
  client.settings.python.analysis.diagnosticMode == 'openFilesOnly',
  'client analysis settings retained'
)
check(
  #notifications == 2
    and notifications[1].method == 'workspace/didChangeConfiguration',
  'Python path notifications retained'
)
vim.lsp.get_clients = get_clients
vim.deprecate = deprecate
check(
  #deprecations == 0,
  'deprecated calls: ' .. table.concat(deprecations, '\n')
)
print(('nvim_0_12_pyright_deprecations: %d checks passed'):format(checks))
vim.cmd('qa!')
