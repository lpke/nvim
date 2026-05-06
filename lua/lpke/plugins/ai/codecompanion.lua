-- Global functions (Lpke_cc_model, Lpke_cc_adapter) are defined as side effects
-- of requiring this module.
require('lpke.plugins.ai.helpers.model_swap')

local cmd_approval = require('lpke.plugins.ai.helpers.cmd_approval')
local ai_config = require('lpke.plugins.ai.helpers.config')
local caveman = require('lpke.plugins.ai.helpers.caveman')
local slash_commands = require('lpke.plugins.ai.helpers.slash_commands')

local function notify(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = 'CodeCompanion' })
end

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
        notify('Chat approvals enabled')
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
                default = ai_config.adapter_default_model('copilot'),
              },
            },
          })
        end,
        opts = {
          show_presets = false,
          show_model_choices = true,
        },
      },
      acp = {
        codex = function()
          return require('codecompanion.adapters').extend('codex', {
            commands = {
              -- default reasoning set here to override last-used setting from `codex` CLI
              default = { 'codex-acp', '-c', 'model_reasoning_effort="low"' },
            },
            defaults = {
              auth_method = 'chatgpt',
              session_config_options = {
                model = ai_config.adapter_default_model('codex'),
                mode = 'Full Access',
              },
            },
          })
        end,
        opts = {
          show_presets = false,
        },
      },
    },
    display = {
      chat = {
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
            return caveman.llm_role(adapter)
          end,
        },
        opts = {
          system_prompt = function(ctx)
            return caveman.system_prompt(ctx)
          end,
        },
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
              notify('Chat submitted')
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
          clear = {
            modes = { n = 'gx' },
            index = 6,
            callback = function(chat)
              chat:clear()
              notify('Chat cleared')
            end,
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
            callback = function(chat)
              local cc_config = require('codecompanion.config')
              local utils = require('codecompanion.utils')
              local chat_fns = require('lpke.plugins.ai.helpers.chat_functions')
              local change_adapter = require(
                'codecompanion.interactions.chat.keymaps.change_adapter'
              )

              if cc_config.display.chat.show_settings then
                return utils.notify(
                  "Adapter can't be changed when `display.chat.show_settings = true`",
                  vim.log.levels.WARN
                )
              end

              local from_adapter = chat.adapter
              local current_adapter = chat.adapter.name
              local adapters_list =
                change_adapter.get_adapters_list(current_adapter)

              vim.ui.select(adapters_list, {
                prompt = 'Select Adapter',
                kind = 'codecompanion.nvim',
                format_item = function(adapter)
                  if adapter == current_adapter then
                    return '* ' .. adapter
                  end
                  return '  ' .. adapter
                end,
              }, function(selected_adapter)
                if not selected_adapter then
                  return
                end

                local function on_adapter_ready()
                  chat_fns.sync_http_tools_for_adapter_change(
                    chat.bufnr,
                    from_adapter,
                    chat.adapter
                  )

                  caveman.refresh_system_prompt(chat)

                  return change_adapter.select_model(chat)
                end

                if current_adapter ~= selected_adapter then
                  require('lpke.plugins.ai.helpers.acp_lifecycle').suspend_chat(
                    chat,
                    {
                      stop_request = true,
                      delay_ms = 100,
                      close_chat = false,
                    }
                  )
                  chat:change_adapter(selected_adapter, on_adapter_ready)
                  notify('Chat adapter changed')
                else
                  return on_adapter_ready()
                end
              end)
            end,
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
            callback = function(chat)
              chat:toggle_system_prompt()
              notify('System prompt toggled')
            end,
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
              notify('Chat approvals toggled')
            end,
            description = 'Toggle YOLO mode',
          },
          clear_approvals = {
            modes = { n = 'gtx' },
            index = 19,
            callback = function(chat)
              local approvals =
                require('codecompanion.interactions.chat.tools.approvals')
              approvals:reset(chat.bufnr)
              notify('Chat approvals cleared')
            end,
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
              require('lpke.plugins.ai.helpers.chat_functions').open_new_chat_with_tools({
                from_chat_keymap = true,
              })
            end,
            description = 'Open a new chat',
          },
          history_or_resume = {
            modes = { n = 'gh' },
            index = 23,
            callback = function(chat)
              require('lpke.plugins.ai.helpers.history_or_resume').open(chat)
            end,
            description = 'Open chat history',
          },
          delete_chat = {
            modes = { n = 'gX' },
            index = 24,
            callback = function(chat)
              require('lpke.plugins.ai.helpers.chat_functions').delete_current_chat(
                chat
              )
            end,
            description = 'Delete current chat',
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
          -- Keep the extension mapping out of the way. The public `gh`
          -- mapping above can choose between ACP `/resume` and saved history.
          keymap = '<Plug>(CodeCompanionHistory)',
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
            adapter = ai_config.defaults.title_generation_adapter,
            ---Model for generating titles (defaults to active chat's model, if nil)
            model = ai_config.model_id(
              ai_config.defaults.title_generation_model
            ),
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

  require('lpke.plugins.ai.helpers.acp_lifecycle').setup()

  -- codecompanion-history hard-codes a leading "✨ " when it renames chat
  -- buffers. It fires this event with the unprefixed title immediately after
  -- setting the name, so use that as a narrow post-processing hook.
  vim.api.nvim_create_autocmd('User', {
    pattern = 'CodeCompanionHistoryTitleSet',
    group = vim.api.nvim_create_augroup('CodeCompanionHistoryTitleClean', {
      clear = true,
    }),
    callback = function(args)
      local data = args.data or {}
      local bufnr = data.bufnr
      local title = data.title

      if
        type(bufnr) ~= 'number'
        or type(title) ~= 'string'
        or not vim.api.nvim_buf_is_valid(bufnr)
      then
        return
      end

      local function try_title(candidate)
        return pcall(vim.api.nvim_buf_set_name, bufnr, candidate)
      end

      if try_title(title) then
        return
      end

      for attempt = 1, 10 do
        if try_title(title .. ' (' .. attempt .. ')') then
          return
        end
      end
    end,
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
