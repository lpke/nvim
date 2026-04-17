-- Global functions (Lpke_toggle_cc, Lpke_cc_model) are defined as side
-- effects of requiring these modules.
require('lpke.plugins.ai.helpers.chat_functions')
require('lpke.plugins.ai.helpers.model_swap')

local cmd_approval = require('lpke.plugins.ai.helpers.cmd_approval')
local slash_commands = require('lpke.plugins.ai.helpers.slash_commands')

local function config()
  local codecompanion = require('codecompanion')

  local spinner = require('lpke.plugins.ai.helpers.chat_spinner')
  spinner:init()

  -- Enable YOLO mode by default on every new chat buffer
  vim.api.nvim_create_autocmd('User', {
    pattern = 'CodeCompanionChatCreated',
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if bufnr then
        require('codecompanion.interactions.chat.tools.approvals'):toggle_yolo_mode(
          bufnr
        )
      end
    end,
  })

  -- Set up keymaps and commands
  require('lpke.plugins.ai.helpers.keymaps').setup()

  codecompanion.setup({
    adapters = {
      http = {
        copilot = function()
          return require('codecompanion.adapters').extend('copilot', {
            schema = {
              model = {
                default = 'claude-opus-4.6', -- premium requests (x3)
                -- default = 'claude-sonnet-4.6', -- premium requests (x1)
                -- default = 'gpt-4o', -- unlimited free
                -- default = 'gpt-4.1', -- unlimited free (better at code)
                -- default = 'gpt-5-mini', -- unlimited free (smarter than 4.1 but dumb contextually)
              },
            },
          })
        end,
        opts = {
          show_presets = false,
          show_model_choices = true,
        },
      },
    },
    display = {
      chat = {
        intro_message = 'g? for options',
        show_header_separator = false,
      },
    },
    interactions = {
      -- CHAT STRATEGY ----------------------------------------------------------
      chat = {
        tools = {
          -- Override tool descriptions to support absolute paths outside cwd,
          -- but ONLY when the user has explicitly shared an external directory
          -- via the /external_files slash command.
          ['read_file'] = {
            description = 'Read the contents of a file in the current working directory. Also supports absolute paths for files in external directories, but ONLY if the user has explicitly shared that directory via the /external_files slash command.',
          },
          ['create_file'] = {
            description = 'Create a new file in the current working directory. Also supports absolute paths for files in external directories, but ONLY if the user has explicitly shared that directory via the /external_files slash command.',
          },
          ['insert_edit_into_file'] = {
            description = 'Edit existing files with multiple automatic fallback interactions. Works on files in the current working directory. Also supports absolute paths for files in external directories, but ONLY if the user has explicitly shared that directory via the /external_files slash command.',
          },
          ['file_search'] = {
            description = 'Search for files by glob pattern in the current working directory. For searching in external directories, use run_command instead.',
          },
          ['grep_search'] = {
            description = 'Search for text in files in the current working directory. For searching in external directories, use run_command instead.',
          },
          ['delete_file'] = {
            description = 'Delete a file. Only works for files within the current working directory.',
            opts = {
              allowed_in_yolo_mode = true,
            },
          },
          ['run_command'] = {
            opts = {
              require_cmd_approval = true,
              require_approval_before = cmd_approval,
            },
          },
          opts = {
            wait_timeout = 120000, -- time to accept edit
          },
        },
        keymaps = {
          options = {
            modes = { n = 'g?' },
            callback = 'keymaps.options',
            description = 'Options',
            hide = true,
          },
          completion = {
            modes = { i = '<C-_>' },
            index = 1,
            callback = 'keymaps.completion',
            description = 'Completion Menu',
          },
          send = {
            modes = {
              n = { '<CR>', '<C-s>' },
              i = '<C-s>',
            },
            index = 2,
            callback = function(chat)
              vim.cmd('stopinsert')
              chat:submit()
            end,
            description = 'Send',
          },
          regenerate = {
            modes = { n = 'gr' },
            index = 3,
            callback = 'keymaps.regenerate',
            description = 'Regenerate the last response',
          },
          close = {
            modes = { n = '<C-c>', i = '<C-c>' },
            index = 4,
            callback = 'keymaps.close',
            description = 'Close Chat',
          },
          stop = {
            modes = { n = 'Q' },
            index = 5,
            callback = 'keymaps.stop',
            description = 'Stop Request',
          },
          clear = {
            modes = { n = 'gx' },
            index = 6,
            callback = 'keymaps.clear',
            description = 'Clear Chat',
          },
          codeblock = {
            modes = { n = 'gc' },
            index = 7,
            callback = 'keymaps.codeblock',
            description = 'Insert Codeblock',
          },
          yank_code = {
            modes = { n = 'gy' },
            index = 8,
            callback = 'keymaps.yank_code',
            description = 'Yank Code',
          },
          -- pin and watch no longer exist in v19
          -- replaced by buffer_sync_all and buffer_sync_diff
          buffer_sync_all = {
            modes = { n = 'gp' },
            index = 9,
            callback = 'keymaps.buffer_sync_all',
            description = 'Toggle buffer syncing',
          },
          buffer_sync_diff = {
            modes = { n = 'gw' },
            index = 10,
            callback = 'keymaps.buffer_sync_diff',
            description = 'Toggle buffer diff syncing',
          },
          next_chat = {
            modes = { n = 'g.' },
            index = 11,
            callback = 'keymaps.next_chat',
            description = 'Next Chat',
          },
          previous_chat = {
            modes = { n = 'g,' },
            index = 12,
            callback = 'keymaps.previous_chat',
            description = 'Previous Chat',
          },
          next_header = {
            modes = { n = ']]' },
            index = 13,
            callback = 'keymaps.next_header',
            description = 'Next Header',
          },
          previous_header = {
            modes = { n = '[[' },
            index = 14,
            callback = 'keymaps.previous_header',
            description = 'Previous Header',
          },
          change_adapter = {
            modes = { n = 'ga' },
            index = 15,
            callback = 'keymaps.change_adapter',
            description = 'Change adapter',
          },
          fold_code = {
            modes = { n = 'gf' },
            index = 15,
            callback = 'keymaps.fold_code',
            description = 'Fold code',
          },
          debug = {
            modes = { n = 'gD' },
            index = 16,
            callback = 'keymaps.debug',
            description = 'View debug info',
          },
          system_prompt = {
            modes = { n = 'gs' },
            index = 17,
            callback = 'keymaps.toggle_system_prompt',
            description = 'Toggle the system prompt',
          },
          yolo_mode = {
            modes = { n = 'gta' },
            index = 20,
            callback = function(chat)
              local approvals =
                require('codecompanion.interactions.chat.tools.approvals')
              approvals:toggle_yolo_mode(chat.bufnr)
              require('lualine').refresh()
            end,
            description = 'Toggle YOLO mode',
          },
          clear_approvals = {
            modes = { n = 'gtx' },
            index = 19,
            callback = 'keymaps.clear_approvals',
            description = 'Clear approvals',
          },
          goto_file_under_cursor = {
            modes = { n = 'gd' },
            index = 21,
            callback = 'keymaps.goto_file_under_cursor',
            description = 'Open the file under cursor in a new tab.',
          },
          new_chat = {
            modes = { n = 'gn' },
            index = 22,
            callback = function()
              vim.cmd('CodeCompanionChat')
            end,
            description = 'Open a new chat',
          },
          delete_chat = {
            modes = { n = 'gX' },
            index = 23,
            callback = function()
              local cur_chat =
                require('codecompanion.interactions.chat').buf_get_chat(0)
              local save_id = cur_chat.opts.save_id
              require('codecompanion').extensions.history.delete_chat(save_id)
              cur_chat:close()
              vim.cmd('CodeCompanionChat')
            end,
            description = 'Delete current chat and open a new one',
          },
        },
        slash_commands = slash_commands,
        shared = {
          editor_context = {
            ['buffer'] = {
              opts = {
                default_params = 'diff',
              },
            },
          },
        },
      },
      -- INLINE STRATEGY --------------------------------------------------------
      inline = {},
    },
    extensions = {
      history = {
        enabled = true,
        opts = {
          -- Keymap to open history from chat buffer (default: gh)
          keymap = 'gh',
          -- Keymap to save the current chat manually (when auto_save is disabled)
          save_chat_keymap = 'gsc',
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
            adapter = 'copilot', -- e.g "copilot"
            ---Model for generating titles (defaults to active chat's model, if nil)
            model = 'gpt-5-mini', -- e.g "gpt-5-mini"
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

  -- Patch the ask_questions tool to use a Telescope picker with
  -- wrapped text and a preview pane instead of the default vim.ui.select
  -- which truncates long questions and option descriptions.
  require('lpke.plugins.ai.helpers.ask_questions_ui').patch()

  -- Suppress CodeCompanion's notify log handler to prevent blocking
  -- "Press Enter" prompts on tool errors. Errors are still written to
  -- the log file (~/.local/state/nvim/codecompanion.log).
  local root_logger = require('codecompanion.utils.log').get_root()
  if root_logger then
    for _, handler in ipairs(root_logger:get_handlers()) do
      if handler.type == 'notify' then
        handler.handle = function() end
        break
      end
    end
  end
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
    {
      'ravitemer/codecompanion-history.nvim',
    },
  },
}
