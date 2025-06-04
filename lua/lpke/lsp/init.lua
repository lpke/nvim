-- everything to be accessible from `lpke.lsp`
require('lpke.lsp.globals')

local enabled_language_servers = {
  'html',
  'cssls',
  'tailwindcss',
  'ts_ls', -- formerly: `tsserver`
  'eslint',
  'jsonls',
  'graphql',
  'lua_ls',
  'vimls',
  'emmet_ls',
  'bashls',
  'pyright',
}

local config_overrides = {}
for _, server in ipairs(enabled_language_servers) do
  local status, config = pcall(require, 'lpke.lsp.' .. server)
  if status and config then
    config_overrides[server] = config
  else
    config_overrides[server] = {}
  end
end

return {
  enabled_language_servers = enabled_language_servers,
  -- { ...<server> = require('lpke.lsp.<server>') || {} }
  config_overrides = config_overrides,
}
