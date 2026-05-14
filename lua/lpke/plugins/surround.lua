local function config()
  require('nvim-surround').setup({
    move_cursor = false,
  })
end

return {
  'kylechui/nvim-surround',
  commit = '7a7a78a52219a3312c1fcabf880cea07a7956a5f',
  version = '*', -- stable
  event = 'VeryLazy',
  config = config,
}
