local function config()
  local helpers = require('lpke.core.helpers')
end

return {
  'L3MON4D3/LuaSnip',
  version = 'v2.*', -- follow latest release
  build = 'make install_jsregexp',
  'stevearc/dressing.nvim',
  config = config,
}
