return {
  on_init = function(_client, _result)
    -- when server first initiated
  end,
  on_attach = function(_client, _bufnr)
    -- for every buffer attach
  end,
  settings = {
    rulesCustomizations = {
      -- {
      --   rule = '*exhaustive-deps',
      --   severity = 'off',
      -- },
      -- {
      --   rule = '*no-unused-vars',
      --   severity = 'off',
      -- },
      -- {
      --   rule = 'prettier/prettier',
      --   severity = 'warn',
      -- },
    },
  },
}
