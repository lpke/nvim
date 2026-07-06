-- formerly: `tsserver`
local js_project_shape = require('lpke.lsp.helpers.js_project_shape')

local vue_language_server_path = vim.fn.stdpath('data')
  .. '/mason/packages/vue-language-server/node_modules/@vue/language-server'

local function import_module_specifier_ending(root_dir)
  local uses_bundler_resolution =
    js_project_shape.uses_bundler_resolution(root_dir)

  return uses_bundler_resolution and 'minimal' or 'js'
end

local function apply_import_specifier_preferences(config, root_dir)
  config.init_options = config.init_options or {}
  config.init_options.preferences =
    vim.tbl_deep_extend('force', config.init_options.preferences or {}, {
      importModuleSpecifierPreference = 'non-relative', -- use absolute/non-relative import paths if possible
      importModuleSpecifierEnding = import_module_specifier_ending(root_dir),
    })
end

return {
  before_init = function(_, config)
    apply_import_specifier_preferences(config, config.root_dir)
  end,
  on_new_config = function(config, root_dir)
    apply_import_specifier_preferences(config, root_dir)
  end,
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
        configNamespace = 'typescript',
      },
    },
  },
  settings = Lpke_ts_ls_settings(),
}
