local ai_config = require('lpke.plugins.ai.helpers.config')
local img_clip = require('lpke.plugins.ai.helpers.img_clip')
local slash_commands = require('lpke.plugins.ai.helpers.slash_commands')
local submit_guard = require('lpke.plugins.ai.helpers.submit_guard')

local function notify(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = 'CodeCompanion' })
end

local function patch_copilot_token_error_notify()
  local token = require('codecompanion.adapters.http.copilot.token')
  if token._lpke_missing_token_notify then
    return
  end
  token._lpke_missing_token_notify = true

  local missing_token_notified = false
  local original_init = token.init
  token.init = function(...)
    local ok = original_init(...)
    if ok or missing_token_notified then
      return ok
    end

    local state = token.fetch()
    if state and state.oauth_token then
      return ok
    end

    missing_token_notified = true
    vim.schedule(function()
      vim.notify(
        'GitHub Copilot token missing; run :Copilot auth',
        vim.log.levels.ERROR,
        { title = 'CodeCompanion' }
      )
    end)
    return ok
  end
end

local function setup_submit_scroll_top()
  vim.api.nvim_create_autocmd('User', {
    pattern = 'CodeCompanionChatSubmitted',
    group = vim.api.nvim_create_augroup('LpkeCodeCompanionSubmitScrollTop', {
      clear = true,
    }),
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end

        for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
          if vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_call, win, function()
              vim.cmd('normal! zt')
            end)
          end
        end
      end)
    end,
  })
end

local function config()
  local codecompanion = require('codecompanion')

  local spinner = require('lpke.plugins.ai.helpers.chat_spinner')
  spinner:init()

  -- Set up keymaps and commands
  require('lpke.plugins.ai.helpers.keymaps').setup()
  setup_submit_scroll_top()

  local options = {
    rules = {
      opts = {
        chat = {
          enabled = false,
        },
      },
    },
    adapters = {
      http = {
        copilot = function()
          return require('codecompanion.adapters').extend('copilot', {
            schema = {
              model = {
                default = ai_config.adapter_default_model('copilot'),
              },
            },
          })
        end,
        opts = { show_presets = false, show_model_choices = true },
      },
      acp = {
        codex = function()
          local adapter = require('codecompanion.adapters').extend('codex', {
            commands = {
              default = {
                'codex-acp-exec',
              },
            },
            -- New Codex ACP sessions inherit CLI state unless explicitly overridden.
            env = {
              CODEX_PATH = function()
                local path = vim.fn.exepath('codex')
                return path ~= '' and path or nil
              end,
              CODEX_CONFIG = function()
                return vim.json.encode({
                  model = ai_config.adapter_default_model('codex'),
                  model_reasoning_effort = ai_config.adapter_default_reasoning_effort(
                    'codex'
                  ),
                })
              end,
            },
            defaults = {
              auth_method = 'chat-gpt',
              session_config_options = {
                model = ai_config.adapter_default_model('codex'),
                mode = 'agent-full-access',
                thought_level = ai_config.adapter_default_reasoning_effort(
                  'codex'
                ),
              },
            },
          })

          -- The stock adapter treats an unset variable name as its literal value.
          -- Never pass that placeholder to codex-acp, which can persist it globally.
          adapter.env.OPENAI_API_KEY = nil
          adapter.env.CODEX_API_KEY = nil
          adapter.handlers.request.build_messages =
            submit_guard.wrap_acp_build_messages(
              adapter.handlers.request.build_messages
            )
          return adapter
        end,
        opts = { show_presets = false },
      },
    },
    display = {
      chat = {
        fold_reasoning = false,
        intro_message = '',
        show_header_separator = false,
      },
    },
    interactions = {
      -- CHAT STRATEGY ----------------------------------------------------------
      chat = {
        adapter = ai_config.defaults.chat_adapter,
        roles = {
          llm = function(adapter)
            local name = adapter.formatted_name
              or adapter.name
              or adapter.type
              or 'LLM'
            return 'CodeCompanion (' .. name .. ')'
          end,
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
              submit_guard.submit(chat)
            end,
            description = 'Send',
          },
          regenerate = {
            modes = { n = 'gr' },
            index = 3,
            callback = function(chat)
              chat:regenerate()
              notify('Chat regenerated')
            end,
            description = 'Regenerate the last response',
          },
          close = {
            modes = { n = '<C-c>', i = '<C-c>' },
            index = 4,
            callback = function(chat)
              chat:close()
              notify('Chat closed')

              local chats = require('codecompanion').buf_get_chat()
              if vim.tbl_count(chats) == 0 then
                return
              end

              local window_opts = chat.ui.window_opts or { default = true }
              chats[1].chat.ui:open({ window_opts = window_opts })
              notify('Chat opened')
            end,
            description = 'Close Chat',
          },
          stop = {
            modes = { n = '<leader>Q' },
            index = 5,
            callback = function(chat)
              if chat.current_request then
                chat:stop()
                notify('Chat stopped')
              else
                notify('No request to stop')
              end
            end,
            description = 'Stop Request',
          },
          clear = false,
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
          -- Keep the familiar pin/watch keys for full/diff context syncing.
          sync_all = {
            modes = { n = 'gp' },
            index = 9,
            callback = 'keymaps.sync_all',
            description = 'Toggle buffer syncing',
          },
          sync_diff = {
            modes = { n = 'gw' },
            index = 10,
            callback = 'keymaps.sync_diff',
            description = 'Toggle buffer diff syncing',
          },
          next_chat = {
            modes = { n = 'g.' },
            index = 11,
            callback = function(chat)
              require('lpke.plugins.ai.helpers.chat_functions').swap_chat(
                chat,
                1
              )
            end,
            description = 'Next Chat',
          },
          previous_chat = {
            modes = { n = 'g,' },
            index = 12,
            callback = function(chat)
              require('lpke.plugins.ai.helpers.chat_functions').swap_chat(
                chat,
                -1
              )
            end,
            description = 'Previous Chat',
          },
          chat_picker = {
            modes = { n = 'gl' },
            index = 13,
            callback = function()
              require('lpke.plugins.ai.helpers.chat_picker').open()
            end,
            description = 'Open Chat Picker',
          },
          next_header = {
            modes = { n = ']]' },
            index = 14,
            callback = 'keymaps.next_header',
            description = 'Next Header',
          },
          previous_header = {
            modes = { n = '[[' },
            index = 15,
            callback = 'keymaps.previous_header',
            description = 'Previous Header',
          },
          change_adapter = {
            modes = { n = 'ga' },
            index = 16,
            callback = require('lpke.plugins.ai.helpers.model_swap').show_adapter_picker,
            description = 'Change adapter/model',
          },
          fold_code = {
            modes = { n = 'gf' },
            index = 17,
            callback = 'keymaps.fold_code',
            description = 'Fold code',
          },
          debug = {
            modes = { n = 'gD' },
            index = 18,
            callback = 'keymaps.debug',
            description = 'View debug info',
          },
          system_prompt = false,
          yolo_mode = false,
          clear_approvals = false,
          copilot_stats = false,
          goto_file_under_cursor = {
            modes = { n = 'gd' },
            index = 22,
            callback = function()
              require('lpke.plugins.ai.helpers.reference_jump').open_under_cursor()
            end,
            description = 'Follow link or file path in a tab; pasted images open their directory.',
          },
          new_chat = {
            modes = { n = 'gn' },
            index = 23,
            callback = function()
              require('lpke.plugins.ai.helpers.chat_functions').open_new_chat({
                from_chat_keymap = true,
              })
            end,
            description = 'Open a new chat',
          },
          history = {
            modes = { n = 'gh' },
            index = 24,
            callback = function()
              require('lpke.plugins.ai.helpers.chat_functions').open_history()
            end,
            description = 'Open chat history',
          },
          history_or_resume = {
            modes = { n = 'gH' },
            index = 25,
            callback = function(chat)
              require('lpke.plugins.ai.helpers.history_or_resume').open(chat)
            end,
            description = 'Choose chat history action',
          },
          delete_chat = {
            modes = { n = 'gX' },
            index = 26,
            callback = function(chat)
              chat:close()
              notify('Chat closed')
            end,
            description = 'Close current chat',
          },
        },
        slash_commands = slash_commands,
      },
      shared = {
        editor_context = {
          ['buffer'] = {
            path = 'lpke.plugins.ai.helpers.editor_context.buffer',
            opts = {
              default_params = 'diff',
            },
          },
          ['diagnostics'] = {
            path = 'lpke.plugins.ai.helpers.editor_context.diagnostics',
          },
        },
      },
      -- INLINE STRATEGY --------------------------------------------------------
      inline = {
        adapter = ai_config.defaults.inline_adapter,
      },
      cmd = {
        adapter = ai_config.defaults.cmd_adapter,
      },
    },
    extensions = {
      history = {
        enabled = true,
        opts = {
          -- Native codecompanion-history option for untitled autosaved chats.
          default_buf_title = '[CodeCompanion]  ',
          -- Keep the extension mapping out of the way. The public `gh` mapping
          -- opens saved history, while `gH` chooses between history/actions.
          keymap = '<Plug>(CodeCompanionHistory)',
          -- Keymap to save the current chat manually (when auto_save is disabled)
          save_chat_keymap = 'gsc',
          -- Save all chats by default (disable to save only manually using 'sc')
          auto_save = true,
          -- Number of days after which chats are automatically deleted (0 to disable)
          expiration_days = 14,
          -- Picker interface ("telescope" or "snacks" or "fzf-lua" or "default")
          picker = 'telescope',
          picker_keymaps = {
            rename = {
              n = 'gr',
              i = '<M-r>',
            },
          },
          ---Automatically generate titles for new chats
          auto_generate_title = true,
          -- LPKE generates once through an isolated Codex invocation.
          title_generation_opts = { refresh_every_n_prompts = 0 },
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
  }
  require('lpke.core.local_extensions').call('codecompanion_config', options)
  codecompanion.setup(options)
  -- Summary generation requires HTTP chats; saved summaries remain browsable.
  require('codecompanion.config').interactions.chat.keymaps['Generate Summary'] =
    nil

  patch_copilot_token_error_notify()
  require('lpke.plugins.ai.helpers.keymap_help').setup()
  submit_guard.setup()
  require('lpke.plugins.ai.helpers.auto_continue').setup()
  require('lpke.plugins.ai.helpers.send_in').setup()
  require('lpke.plugins.ai.helpers.slash_command_completion').patch_cmp()
  require('lpke.plugins.ai.helpers.codex_mode').setup()
  require('lpke.plugins.ai.helpers.acp_lifecycle').setup()
  require('lpke.plugins.ai.helpers.history_scope').setup()
  require('lpke.plugins.ai.helpers.history_acp').setup()
  require('lpke.plugins.ai.helpers.history_search').setup()
  require('lpke.plugins.ai.helpers.drafts').setup()
  require('lpke.plugins.ai.helpers.folds').setup()
  require('lpke.plugins.ai.helpers.chat_history').setup()
  require('lpke.plugins.ai.helpers.codex_threads').setup()

  -- CodeCompanion hard-codes Reasoning and Response headings around reasoning.
  require('lpke.plugins.ai.helpers.chat_render').patch()
  require('lpke.plugins.ai.helpers.reasoning_separators').patch()

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

  require('lpke.core.local_extensions').call('codecompanion_ready')
  require('lpke.plugins.ai.helpers.startup_codex').setup()
end

return {
  'olimorris/codecompanion.nvim',
  commit = '142eadffdaa8dd06060646b6f8ef74e99c42ab06',
  config = config,
  dependencies = {
    -- required
    {
      'nvim-lua/plenary.nvim',
      commit = 'b9fd5226c2f76c951fc8ed5923d85e4de065e509',
    },
    {
      'nvim-treesitter/nvim-treesitter',
      branch = 'main',
      commit = 'a2f694478be07f89c2d03cc17858a8745a400c4b',
    },
    -- optionals
    {
      'HakonHarnes/img-clip.nvim',
      commit = 'd8b6b030672f9f551a0e3526347699985a779d93',
      config = function(_, opts)
        require('img-clip').setup(opts)
        img_clip.setup_inline_paste()
        vim.api.nvim_create_user_command('PasteImage', img_clip.paste_image, {
          desc = 'Paste image from system clipboard',
          force = true,
        })
      end,
      opts = {
        default = {
          dir_path = img_clip.dir_path(),
          drag_and_drop = {
            enabled = false,
          },
        },
        filetypes = {
          codecompanion = {
            prompt_for_file_name = false,
            template = '`$FILE_PATH`',
            use_absolute_path = true,
            embed_image_as_base64 = false,
          },
        },
      },
    },
    -- extensions
    -- https://codecompanion.olimorris.dev/extensions/history.html
    {
      'ravitemer/codecompanion-history.nvim',
      commit = 'bc1b4fe06eaaf0aa2399be742e843c22f7f1652a',
    },
  },
}
