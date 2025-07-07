local function config()
  local tsc = require('ts_context_commentstring')

  -- skip backwards compatibility routines, speed up loading
  vim.g.skip_ts_context_commentstring_module = true

  tsc.setup({
    enable_autocmd = false,
  })
end

return {
  'JoosepAlviste/nvim-ts-context-commentstring',
  config = config,
}
