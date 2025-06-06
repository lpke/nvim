local function config()
  local codecompanion = require('codecompanion')

  codecompanion.setup({})
end

return {
  'olimorris/codecompanion.nvim',
  config = config,
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
    {
      'echasnovski/mini.diff',
      config = function()
        local diff = require('mini.diff')
        diff.setup({
          -- Disabled by default
          source = diff.gen_source.none(),
        })
      end,
    },
    {
      'HakonHarnes/img-clip.nvim',
      opts = {
        filetypes = {
          codecompanion = {
            prompt_for_file_name = false,
            template = '[Image]($FILE_PATH)',
            use_absolute_path = true,
          },
        },
      },
    },
  },
}
