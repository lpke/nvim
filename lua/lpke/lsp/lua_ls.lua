return {
  on_init = function(client, result)
    -- when server first initiated
  end,
  on_attach = function(client, bufnr)
    -- for every buffer attach
  end,
  settings = {
    Lua = {
      workspace = {
        checkThirdParty = false,
        library = {
          vim.env.VIMRUNTIME,
          '${3rd}/luv/library',
        },
      },
    },
  },
}
