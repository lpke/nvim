local upstream_on_attach

return {
  on_attach = function(client, bufnr)
    if not upstream_on_attach then
      local path =
        assert(vim.api.nvim_get_runtime_file('lsp/pyright.lua', false)[1])
      upstream_on_attach = dofile(path).on_attach
    end
    upstream_on_attach(client, bufnr)
    vim.api.nvim_buf_create_user_command(
      bufnr,
      'LspPyrightOrganizeImports',
      function()
        client:request('workspace/executeCommand', {
          command = 'pyright.organizeimports',
          arguments = { vim.uri_from_bufnr(bufnr) },
        }, nil, bufnr)
      end,
      { desc = 'Organize Imports' }
    )
  end,
}
