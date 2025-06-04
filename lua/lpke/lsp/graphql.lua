return {
  on_init = function(_client, _result)
    -- when server first initiated
  end,
  on_attach = function(_client, _bufnr)
    -- for every buffer attach
  end,
  settings = {
    filetypes = {
      'graphql',
      'gql',
      'svelte',
      'typescriptreact',
      'javascriptreact',
    },
  },
}
