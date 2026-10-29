local function config()
  -- options
  require('nvim-treesitter-textobjects').setup({
    -- config
  })
end

return {
  'nvim-treesitter/nvim-treesitter-textobjects',
  branch = 'main',
  commit = '5c7b0263797dfd1bd6202f2b219f3b53a80b2187',
  config = config,
}
