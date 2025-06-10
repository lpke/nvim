local function config()
  local codecompanion = require('codecompanion')
  local helpers = require('lpke.core.helpers')

  local spinner = require('lpke.plugins.ai.helpers.chat-spinner')
  spinner:init()

  -- stylua: ignore start
  helpers.keymap_set_multi({
    { 'nvC', '<A-f>', 'CodeCompanionChat Toggle', { desc = 'CodeCompanion: Open a chat buffer' }},
    { 'nvC', '<F2>f', 'CodeCompanionChat Toggle', { desc = 'CodeCompanion: Open a chat buffer' }},
    { 'niC', '<C-l>', 'CodeCompanion', { desc = 'CodeCompanion: Open inline dialog' }},
    { 'v', '<C-l>', ":<C-u>'<,'>CodeCompanion<cr>", { desc = 'CodeCompanion: Open inline dialog (visual selection)' }},
  })
  -- stylua: ignore end

  codecompanion.setup({
    adapters = {
      copilot = function()
        return require('codecompanion.adapters').extend('copilot', {
          schema = {
            model = {
              default = 'claude-sonnet-4',
            },
          },
        })
      end,
      opts = {
        show_defaults = false,
        show_model_choices = true,
      },
    },
    display = {
      chat = {
        intro_message = 'g? for options',
        show_header_separator = false,
      },
    },
    strategies = {
      chat = {
        keymaps = {
          options = {
            modes = {
              n = 'g?',
            },
            callback = 'keymaps.options',
            description = 'Options',
            hide = true,
          },
          completion = {
            modes = {
              i = '<C-_>',
            },
            index = 1,
            callback = 'keymaps.completion',
            description = 'Completion Menu',
          },
          send = {
            modes = {
              n = { '<CR>', '<C-s>' },
              i = '<C-s>',
            },
            callback = function(chat)
              vim.cmd('stopinsert')
              chat:submit()
            end,
            index = 2,
            description = 'Send',
          },
          regenerate = {
            modes = {
              n = 'gr',
            },
            index = 3,
            callback = 'keymaps.regenerate',
            description = 'Regenerate the last response',
          },
          close = {
            modes = {
              n = '<C-c>',
              i = '<C-c>',
            },
            index = 4,
            callback = 'keymaps.close',
            description = 'Close Chat',
          },
          stop = {
            modes = {
              n = 'q',
            },
            index = 5,
            callback = 'keymaps.stop',
            description = 'Stop Request',
          },
          clear = {
            modes = {
              n = 'gx',
            },
            index = 6,
            callback = 'keymaps.clear',
            description = 'Clear Chat',
          },
          codeblock = {
            modes = {
              n = 'gc',
            },
            index = 7,
            callback = 'keymaps.codeblock',
            description = 'Insert Codeblock',
          },
          yank_code = {
            modes = {
              n = 'gy',
            },
            index = 8,
            callback = 'keymaps.yank_code',
            description = 'Yank Code',
          },
          pin = {
            modes = {
              n = 'gp',
            },
            index = 9,
            callback = 'keymaps.pin_reference',
            description = 'Pin Reference',
          },
          watch = {
            modes = {
              n = 'gw',
            },
            index = 10,
            callback = 'keymaps.toggle_watch',
            description = 'Watch Buffer',
          },
          next_chat = {
            modes = {
              n = 'g.',
            },
            index = 11,
            callback = 'keymaps.next_chat',
            description = 'Next Chat',
          },
          previous_chat = {
            modes = {
              n = 'g,',
            },
            index = 12,
            callback = 'keymaps.previous_chat',
            description = 'Previous Chat',
          },
          next_header = {
            modes = {
              n = ']]',
            },
            index = 13,
            callback = 'keymaps.next_header',
            description = 'Next Header',
          },
          previous_header = {
            modes = {
              n = '[[',
            },
            index = 14,
            callback = 'keymaps.previous_header',
            description = 'Previous Header',
          },
          change_adapter = {
            modes = {
              n = 'ga',
            },
            index = 15,
            callback = 'keymaps.change_adapter',
            description = 'Change adapter',
          },
          fold_code = {
            modes = {
              n = 'gf',
            },
            index = 15,
            callback = 'keymaps.fold_code',
            description = 'Fold code',
          },
          debug = {
            modes = {
              n = 'gD',
            },
            index = 16,
            callback = 'keymaps.debug',
            description = 'View debug info',
          },
          system_prompt = {
            modes = {
              n = 'gs',
            },
            index = 17,
            callback = 'keymaps.toggle_system_prompt',
            description = 'Toggle the system prompt',
          },
          auto_tool_mode = {
            modes = {
              n = 'gta',
            },
            index = 18,
            callback = 'keymaps.auto_tool_mode',
            description = 'Toggle automatic tool mode',
          },
          goto_file_under_cursor = {
            modes = { n = 'gd' },
            index = 19,
            callback = 'keymaps.goto_file_under_cursor',
            description = 'Open the file under cursor in a new tab.',
          },
        },
      },
    },
    extensions = {
      history = {
        enabled = true,
        opts = {
          -- Keymap to open history from chat buffer (default: gh)
          keymap = 'gh',
          -- Keymap to save the current chat manually (when auto_save is disabled)
          save_chat_keymap = 'sc',
          -- Save all chats by default (disable to save only manually using 'sc')
          auto_save = true,
          -- Number of days after which chats are automatically deleted (0 to disable)
          expiration_days = 14,
          -- Picker interface ("telescope" or "snacks" or "fzf-lua" or "default")
          picker = 'telescope',
          ---Automatically generate titles for new chats
          auto_generate_title = true,
          title_generation_opts = {
            ---Adapter for generating titles (defaults to active chat's adapter, if nil)
            adapter = nil, -- e.g "copilot"
            ---Model for generating titles (defaults to active chat's model, if nil)
            model = 'gpt-4o', -- e.g "gpt-4o"
            refresh_every_n_prompts = 1,
            max_refreshes = 3,
          },
          ---On exiting and entering neovim, loads the last chat on opening chat
          continue_last_chat = false,
          ---When chat is cleared with `gx` delete the chat from history
          delete_on_clearing_chat = false,
          ---Directory path to save the chats
          dir_to_save = vim.fn.stdpath('data') .. '/codecompanion-history',
          ---Enable detailed logging for history extension
          enable_logging = false,
        },
      },
    },
  })
end

return {
  'olimorris/codecompanion.nvim',
  config = config,
  dependencies = {
    -- required
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
    -- optionals
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
    -- extensions
    -- https://codecompanion.olimorris.dev/extensions/history.html
    'ravitemer/codecompanion-history.nvim',
  },
}
