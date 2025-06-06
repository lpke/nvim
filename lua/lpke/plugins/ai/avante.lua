local function config()
  local avante = require('avante')

  -- full default options:
  -- https://github.com/yetone/avante.nvim/blob/main/lua/avante/config.lua
  avante.setup({
    provider = 'claude',
    providers = {
      claude = {
        -- model names: https://docs.anthropic.com/en/docs/about-claude/models/overview#model-names
        -- model costs: https://docs.anthropic.com/en/docs/about-claude/models/overview#model-pricing
        endpoint = 'https://api.anthropic.com',
        model = 'claude-sonnet-4-20250514',
        timeout = 45000, -- ms (increase for reasoning models)
        extra_request_body = {
          temperature = 0.75,
          max_tokens = 20480,
        },
      },
      ['claude-haiku'] = {
        __inherited_from = 'claude',
        model = 'claude-3-5-haiku-latest',
        timeout = 30000,
        extra_request_body = {
          temperature = 0.75,
          max_tokens = 8192,
        },
      },
      ['claude-opus'] = {
        __inherited_from = 'claude',
        model = 'claude-opus-4-20250514	',
        timeout = 60000,
        extra_request_body = {
          temperature = 0.75,
          max_tokens = 20480,
        },
      },
      openai = {
        endpoint = 'https://api.openai.com/v1',
        model = 'gpt-4o',
        extra_request_body = {
          timeout = 30000,
          temperature = 0.75,
          max_completion_tokens = 8192, -- Increase this to include reasoning tokens (for reasoning models)
          --reasoning_effort = "medium", -- low|medium|high, only used for reasoning models
        },
      },
      ['openai-gpt-4o-mini'] = {
        __inherited_from = 'openai',
        model = 'gpt-4o-mini',
      },
      copilot = {
        endpoint = 'https://api.githubcopilot.com',
        model = 'gpt-4o-2024-11-20',
        proxy = nil, -- [protocol://]host[:port] Use this proxy
        allow_insecure = false, -- Allow insecure server connections
        timeout = 30000,
        extra_request_body = {
          temperature = 0.75,
          max_tokens = 20480,
        },
      },
      gemini = {
        endpoint = 'https://generativelanguage.googleapis.com/v1beta/models',
        model = 'gemini-2.0-flash',
        timeout = 30000,
        use_ReAct_prompt = true,
        extra_request_body = {
          generationConfig = {
            temperature = 0.75,
          },
        },
      },
      ollama = {
        endpoint = 'http://127.0.0.1:11434',
        timeout = 30000,
        extra_request_body = {
          options = {
            temperature = 0.75,
            num_ctx = 20480,
            keep_alive = '5m',
          },
        },
      },
      -- DISABLED (workaround)
      -- These would show up when I didn't want them to, so I set them to
      -- inherit from a provider I'll never use, because fuck micro$oft
      ['vertex'] = {
        __inherited_from = 'cohere',
      },
      ['vertex_claude'] = {
        __inherited_from = 'cohere',
      },
      ['bedrock'] = {
        __inherited_from = 'cohere',
      },
      ['aihubmix'] = {
        __inherited_from = 'cohere',
      },
      ['aihubmix-claude'] = {
        __inherited_from = 'cohere',
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
  init = function()
    vim.env.ANTHROPIC_API_KEY =
      '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'
    -- vim.env.OPENAI_API_KEY = ''
  end,
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
