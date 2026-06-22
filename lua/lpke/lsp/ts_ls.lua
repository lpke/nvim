-- formerly: `tsserver`
local vue_language_server_path = vim.fn.stdpath('data')
  .. '/mason/packages/vue-language-server/node_modules/@vue/language-server'

return {
  on_init = function(_client, _result)
    -- when server first initiated
  end,
  on_attach = function(_client, _bufnr)
    -- for every buffer attach
  end,
  filetypes = {
    'javascript',
    'javascriptreact',
    'javascript.jsx',
    'typescript',
    'typescriptreact',
    'typescript.tsx',
    'vue',
  },
  init_options = {
    hostInfo = 'neovim',
    plugins = {
      {
        name = '@vue/typescript-plugin',
        location = vue_language_server_path,
        languages = { 'vue' },
      },
    },
    preferences = {
      importModuleSpecifierPreference = 'non-relative', -- use absolute/non-relative import paths if possible
      importModuleSpecifierEnding = 'minimal', -- shorten path ending if possible (omit `.ts` etc)
    },
  },
  settings = Lpke_ts_unused_diagnostics_settings(),
}
