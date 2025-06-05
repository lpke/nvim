local function config()
  local avante = require('avante')

  -- full default options:
  -- https://github.com/yetone/avante.nvim/blob/main/lua/avante/config.lua
  avante.setup({
    provider = 'openai',
    providers = {
      openai = {
        endpoint = 'https://api.openai.com/v1',
        model = 'gpt-4o', -- your desired model (or use gpt-4o, etc.)
        extra_request_body = {
          timeout = 30000, -- Timeout in milliseconds, increase this for reasoning models
          temperature = 0.75,
          max_completion_tokens = 8192, -- Increase this to include reasoning tokens (for reasoning models)
          --reasoning_effort = "medium", -- low|medium|high, only used for reasoning models
        },
      },
    },
    hints = {
      enabled = false,
    },
    windows = {
      position = 'right',
      fillchars = 'eob: ',
      wrap = true, -- similar to vim.o.wrap
      width = 30, -- default % based on available width in vertical layout
      height = 30, -- default % based on available height in horizontal layout
      sidebar_header = {
        enabled = false, -- true, false to enable/disable the header
        align = 'center', -- left, center, right for title
        rounded = false,
      },
      input = {
        prefix = '❯ ',
        height = 6, -- Height of the input window in vertical layout
      },
      edit = {
        border = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
        start_insert = true, -- Start insert mode when opening the edit window
      },
      ask = {
        floating = false, -- Open the 'AvanteAsk' prompt in a floating window
        border = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
        start_insert = true, -- Start insert mode when opening the ask window
        focus_on_apply = 'ours', -- which diff to focus after applying
      },
    },
    mappings = {
      diff = {
        ours = 'co',
        theirs = 'ct',
        all_theirs = 'ca',
        both = 'cb',
        cursor = 'cc',
        next = ']x',
        prev = '[x',
      },
      suggestion = {
        accept = '<M-l>',
        next = '<M-]>',
        prev = '<M-[>',
        dismiss = '<C-]>',
      },
      jump = {
        next = ']]',
        prev = '[[',
      },
      submit = {
        normal = '<CR>',
        insert = '<C-s>',
      },
      cancel = {
        normal = { '<C-c>', '<Esc>', 'q' },
        insert = { '<C-c>' },
      },
      ask = '<leader>aa',
      new_ask = '<leader>an',
      edit = '<leader>ae',
      refresh = '<leader>ar',
      focus = '<leader>af',
      stop = '<leader>aS',
      toggle = {
        default = '<leader>at',
        debug = '<leader>ad',
        hint = '<leader>ah',
        suggestion = '<leader>as',
        repomap = '<leader>aR',
      },
      sidebar = {
        apply_all = 'A',
        apply_cursor = 'a',
        retry_user_request = 'r',
        edit_user_request = 'e',
        switch_windows = '<Tab>',
        reverse_switch_windows = '<S-Tab>',
        remove_file = 'd',
        add_file = '@',
        close = { 'q' },
        close_from_input = nil, -- e.g., { normal = "<Esc>", insert = "<C-d>" }
      },
      files = {
        add_current = '<leader>ac', -- Add current buffer to selected files
        add_all_buffers = '<leader>aB', -- Add all buffer files to selected files
      },
      select_model = '<leader>a?', -- Select model command
      select_history = '<leader>ah', -- Select history command
    },
  })
end

return {
  'yetone/avante.nvim',
  event = 'VeryLazy',
  version = false, -- Never set this value to "*"! Never!
  config = config,
  -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
  build = 'make',
  -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
    'stevearc/dressing.nvim',
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
    --- The below dependencies are optional,
    'echasnovski/mini.pick', -- for file_selector provider mini.pick
    'nvim-telescope/telescope.nvim', -- for file_selector provider telescope
    'hrsh7th/nvim-cmp', -- autocompletion for avante commands and mentions
    'ibhagwan/fzf-lua', -- for file_selector provider fzf
    'nvim-tree/nvim-web-devicons', -- or echasnovski/mini.icons
    'zbirenbaum/copilot.lua', -- for providers='copilot'
    'MeanderingProgrammer/render-markdown.nvim',
    {
      -- support for image pasting
      'HakonHarnes/img-clip.nvim',
      event = 'VeryLazy',
      opts = {
        -- recommended settings
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
          -- required for Windows users
          use_absolute_path = true,
        },
      },
    },
  },
}
