local function config()
  -- options
  require('nvim-treesitter.configs').setup({
    -- config
  })
end

return {
  'nvim-treesitter/nvim-treesitter-textobjects',
  dependencies = {
    'nvim-treesitter/nvim-treesitter-textobjects',
  },
  config = config,
}
