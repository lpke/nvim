local function config()
  -- options
  require('nvim-treesitter.configs').setup({
    -- config
  })
end

return {
  'nvim-treesitter/nvim-treesitter-textobjects',
  commit = '71385f191ec06ffc60e80e6b0c9a9d5daed4824c',
  dependencies = {
    {
      'nvim-treesitter/nvim-treesitter-textobjects',
      commit = '71385f191ec06ffc60e80e6b0c9a9d5daed4824c',
    },
  },
  config = config,
}
