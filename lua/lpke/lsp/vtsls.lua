local vue_language_server_path = vim.fn.stdpath('data')
  .. '/mason/packages/vue-language-server/node_modules/@vue/language-server'

return {
  filetypes = { 'vue' },
  settings = {
    vtsls = {
      tsserver = {
        globalPlugins = {
          {
            name = '@vue/typescript-plugin',
            location = vue_language_server_path,
            languages = { 'vue' },
            configNamespace = 'typescript',
          },
        },
      },
    },
  },
}
