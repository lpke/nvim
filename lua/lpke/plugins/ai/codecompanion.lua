local function config()
  local codecompanion = require('codecompanion')
  local helpers = require('lpke.core.helpers')

  local spinner = require('lpke.plugins.ai.helpers.spinner')
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
    display = {
      chat = {
        intro_message = 'Press ? for options',
        show_header_separator = false,
        keymaps = {
          send = {
            callback = function(chat)
              vim.cmd('stopinsert')
              chat:submit()
            end,
            index = 1,
            description = 'Send',
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
