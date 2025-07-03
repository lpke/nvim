local function config()
  local codecompanion = require('codecompanion')
  local helpers = require('lpke.core.helpers')

  local spinner = require('lpke.plugins.ai.helpers.chat-spinner')
  spinner:init()

  local function toggle_if_already_in_chat()
    if vim.bo.filetype == 'codecompanion' then
      vim.cmd('CodeCompanionChat Toggle')
      return true
    end
    return false
  end

  -- toggle the codecompanion chat buffer
  function Lpke_toggle_cc()
    -- stylua: ignore
    if toggle_if_already_in_chat() then return end
    -- find and close any codecompanion windows in other tabs
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if tab ~= vim.api.nvim_get_current_tabpage() then
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
          local buf = vim.api.nvim_win_get_buf(win)
          if
            vim.api.nvim_get_option_value('filetype', { buf = buf })
            == 'codecompanion'
          then
            vim.api.nvim_win_close(win, false)
            break
          end
        end
      end
    end
    -- toggle codecompanion chat normally
    vim.cmd('CodeCompanionChat Toggle')
    vim.cmd('stopinsert')
  end

  local function open_new_chat_with_context()
    -- stylua: ignore
    if toggle_if_already_in_chat() then return end
    vim.cmd('CodeCompanionChat')
    vim.cmd('normal! i#{buffer} #{lsp}')
    vim.cmd('normal! G2o')
    vim.cmd('stopinsert')
    vim.cmd('normal! i@{insert_edit_into_file} ')
    vim.cmd('stopinsert')
  end

  local function open_new_chat_with_context_selection()
    -- stylua: ignore
    if toggle_if_already_in_chat() then return end
    vim.cmd('CodeCompanionChat')
    vim.cmd('normal! gg}}{i#{buffer} #{lsp}')
    vim.cmd('normal! G2o')
    vim.cmd('stopinsert')
    vim.cmd('normal! i@{insert_edit_into_file} ')
    vim.cmd('stopinsert')
  end

  local function toggle_chat_with_context_selection()
    -- stylua: ignore
    if toggle_if_already_in_chat() then return end
    -- copy selection
    vim.cmd('normal! "vy')
    local selection = vim.fn.getreg('v')
    local filetype = vim.bo.filetype
    -- check for codecompanion windows in current tab
    local cc_win = nil
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if
        vim.api.nvim_buf_is_loaded(buf)
        and vim.api.nvim_get_option_value('filetype', { buf = buf })
          == 'codecompanion'
      then
        cc_win = win
        break
      end
    end
    -- if codecompanion window is already open in current tab, focus it
    if cc_win then
      vim.api.nvim_set_current_win(cc_win)
    else
      -- toggle chat if no codecompanion window exists in current tab
      vim.cmd('CodeCompanionChat Toggle')
    end
    -- insert selection in a code block
    if selection ~= '' then
      vim.cmd('normal! Go#{buffer} #{lsp}')
      vim.cmd('stopinsert')
      local code_block_lines = { '```' .. filetype }
      vim.list_extend(code_block_lines, vim.split(selection, '\n'))
      vim.list_extend(code_block_lines, { '```' })
      vim.api.nvim_put(code_block_lines, 'l', true, true)
      vim.cmd('normal! 2o')
      vim.cmd('stopinsert')
    end
  end

  local function open_inline_prompt_with_context()
    if vim.bo.filetype == 'codecompanion' then
      return
    end
    vim.cmd('CodeCompanion')
    vim.api.nvim_input('#{buffer} ')
  end

  -- stylua: ignore start
  helpers.keymap_set_multi({
    { 'in', '<A-f>', Lpke_toggle_cc, { desc = 'CodeCompanion: Toggle the chat buffer' }},
    { 'in', '<F2>f', Lpke_toggle_cc, { desc = 'CodeCompanion: Toggle the chat buffer' }},
    { 'in', '<A-F>', open_new_chat_with_context, { desc = 'CodeCompanion: Open new chat buffer with context' }},
    { 'in', '<F2>F', open_new_chat_with_context, { desc = 'CodeCompanion: Open new chat buffer with context' }},
    { 'v', '<A-f>', toggle_chat_with_context_selection, { desc = 'CodeCompanion: Toggle chat buffer, add context and selection' }},
    { 'v', '<F2>f', toggle_chat_with_context_selection, { desc = 'CodeCompanion: Toggle chat buffer, add context and selection' }},
    { 'v', '<A-F>', open_new_chat_with_context_selection, { desc = 'CodeCompanion: Open a new chat buffer with context and selection' }},
    { 'v', '<F2>F', open_new_chat_with_context_selection, { desc = 'CodeCompanion: Open a new chat buffer with context and selection' }},
    { 'ni', '<C-l>', open_inline_prompt_with_context, { desc = 'CodeCompanion: Open inline prompt with context' }},
    { 'v', '<C-l>', ":<C-u>'<,'>CodeCompanion<cr>#{buffer} ", { desc = 'CodeCompanion: Open inline prompt with context and selection' }},
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
    tools = {
      opts = {
        wait_timeout = 120000, -- time to accept edit
      },
    },
    strategies = {
      -- CHAT STRATEGY ----------------------------------------------------------
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
          new_chat = {
            modes = {
              n = 'gn',
            },
            index = 20,
            callback = function()
              vim.cmd('CodeCompanionChat')
            end,
            description = 'Open a new chat',
          },
          delete_chat = {
            modes = {
              n = 'gX',
            },
            index = 21,
            callback = function()
              local cur_chat =
                require('codecompanion.strategies.chat').buf_get_chat(0)
              local save_id = cur_chat.opts.save_id
              require('codecompanion').extensions.history.delete_chat(save_id)
              cur_chat:close()
              vim.cmd('CodeCompanionChat')
            end,
            description = 'Delete current chat and open a new one',
          },
        },
        slash_commands = {
          ['git_files'] = {
            description = 'List git files',
            callback = function(chat)
              local handle = io.popen('git ls-files')
              if handle ~= nil then
                local result = handle:read('*a')
                handle:close()
                chat:add_reference(
                  { role = 'user', content = result },
                  'git',
                  '<git_files>'
                )
              else
                return vim.notify(
                  'No git files available',
                  vim.log.levels.INFO,
                  { title = 'CodeCompanion' }
                )
              end
            end,
            opts = {
              contains_code = false,
            },
          },
        },
        variables = {
          ['buffer'] = {
            opts = {
              default_params = 'watch',
            },
          },
          ['lsp'] = {
            opts = {
              default_params = 'watch',
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
