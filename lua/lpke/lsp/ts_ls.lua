-- formerly: `tsserver`
local ts_ls = require('lpke.lsp.helpers.ts_ls')
local js_project_shape = require('lpke.lsp.helpers.js_project_shape')

local vue_language_server_path = vim.fn.stdpath('data')
  .. '/mason/packages/vue-language-server/node_modules/@vue/language-server'

local function set_inferred_project_compiler_options(client)
  if not ts_ls.force_module_detection_for_inferred_projects then
    return
  end

  -- typescript-language-server does not pass moduleDetection through
  -- implicitProjectConfiguration, so send the tsserver request directly.
  client.request('workspace/executeCommand', {
    command = 'typescript.tsserverRequest',
    arguments = {
      'compilerOptionsForInferredProjects',
      {
        options = {
          allowImportingTsExtensions = true,
          allowJs = true,
          allowNonTsExtensions = true,
          allowSyntheticDefaultImports = true,
          checkJs = true,
          module = 99, -- ESNext
          moduleDetection = 3, -- Force
          moduleResolution = 100, -- Bundler
          resolveJsonModule = true,
          sourceMap = true,
          strictFunctionTypes = false,
          strictNullChecks = true,
          target = 11, -- ES2024
        },
      },
    },
  }, function(err)
    if err then
      vim.schedule(function()
        vim.notify(
          'ts_ls: failed to set inferred project compiler options',
          vim.log.levels.WARN
        )
      end)
    end
  end)
end

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
  on_init = function(client, _result)
    -- when server first initiated
    set_inferred_project_compiler_options(client)
  end,
  on_attach = function(client, _bufnr)
    -- for every buffer attach
    vim.defer_fn(function()
      if not client.is_stopped() then
        set_inferred_project_compiler_options(client)
      end
    end, 500)
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
