-- formerly: `tsserver`
return {
  on_init = function(_client, _result)
    -- when server first initiated
  end,
  on_attach = function(_client, _bufnr)
    -- for every buffer attach
  end,
  init_options = {
    preferences = {
      importModuleSpecifierPreference = 'non-relative', -- use absolute/non-relative import paths if possible
      importModuleSpecifierEnding = 'minimal', -- shorten path ending if possible (omit `.ts` etc)
    },
  },
}
