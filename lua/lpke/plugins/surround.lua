local function config()
  require('nvim-surround').setup({
    move_cursor = false,
  })
end

return {
  'kylechui/nvim-surround',
  version = '*', -- stable
  event = 'VeryLazy',
  config = config,
}
