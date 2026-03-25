-- this is for use in the `Lpke_cc_model` function below (for shorthand args)
-- for the lualine short names and the model multipliers, see
-- `plugins/lualine.lua`
local model_maps = {
  -- defaults (duplicates for specific versions below)
  ['son'] = 'claude-sonnet-4.6',
  ['opus'] = 'claude-opus-4.6',
  ['gpt'] = 'gpt-5-mini', -- unlimited
  ['haiku'] = 'claude-haiku-4.5',
  ['gem'] = 'gemini-2.5-pro',
  ['grok'] = 'grok-code-fast-1',

  -- others, if running `Lpke_cc_model` manually
  ['opus4.6'] = 'claude-opus-4.6',
  ['opus4.5'] = 'claude-opus-4.5',
  ['son4.6'] = 'claude-sonnet-4.6',
  ['son4.5'] = 'claude-sonnet-4.5',
  ['son4'] = 'claude-sonnet-4',
  ['haiku4.5'] = 'claude-haiku-4.5',
  ['gpt5.2'] = 'gpt-5.2',
  ['gpt5.1'] = 'gpt-5.1',
  ['gpt5.1cM'] = 'gpt-5.1-codex-max',
  ['gpt5.1c'] = 'gpt-5.1-codex',
  ['gpt5m'] = 'gpt-5-mini', -- unlimited
  ['gpt4.1'] = 'gpt-4.1', -- unlimited
  ['gpt4o'] = 'gpt-4o', -- unlimited
  ['gem2.5'] = 'gemini-2.5-pro',
  ['grok1'] = 'grok-code-fast-1',
}

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

local function get_chat_ref(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  return require('codecompanion').buf_get_chat(bufnr)
end

local function get_cur_model(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local chat = require('codecompanion').buf_get_chat(bufnr)
  if not chat then
    return nil
  end
  local adapter = chat.adapter
  if not adapter then
    return nil
  end
  return adapter.schema.model.default or adapter.opts.model
end

-- cycle through AI models provided in an array (or apply directly if only one)
-- returns name of model swapped to, or nil if error
function Lpke_cc_model(models)
  if vim.bo.filetype ~= 'codecompanion' then
    vim.notify(
      'Lpke_cc_model_swap: Not in a CodeCompanion chat buffer',
      vim.log.levels.ERROR
    )
    return nil
  end
  local cur_chat = get_chat_ref(0)
  if not cur_chat then
    return nil
  end

  -- Normalize input to array
  if type(models) ~= 'table' then
    models = { models }
  end

  -- Resolve all model names through model_maps
  local resolved_models = {}
  for i, m in ipairs(models) do
    resolved_models[i] = model_maps[m] or m
  end

  local cur_model = get_cur_model(0)

  local target_model
  if #resolved_models == 1 then
    -- Only one model provided - apply it directly
    target_model = resolved_models[1]
  else
    -- Multiple models - find current and cycle to next
    local cur_index = nil
    for i, m in ipairs(resolved_models) do
      if m == cur_model then
        cur_index = i
        break
      end
    end
    -- Cycle to next model (or first if not found/at end)
    if cur_index and cur_index < #resolved_models then
      target_model = resolved_models[cur_index + 1]
    else
      target_model = resolved_models[1]
    end
  end

  cur_chat:change_model({ model = target_model })
  return get_cur_model()
end

local function config()
  local codecompanion = require('codecompanion')
  local helpers = require('lpke.core.helpers')

  local spinner = require('lpke.plugins.ai.helpers.chat_spinner')
  spinner:init()

  -- Enable YOLO mode by default on every new chat buffer
  vim.api.nvim_create_autocmd('User', {
    pattern = 'CodeCompanionChatCreated',
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if bufnr then
        require('codecompanion.interactions.chat.tools.approvals'):toggle_yolo_mode(bufnr)
      end
    end,
  })

  local function open_new_chat_with_context()
    if toggle_if_already_in_chat() then
      return
    end
    vim.cmd('CodeCompanionChat')
    vim.cmd('normal! i#{buffer} #{diagnostics}')
    vim.cmd('normal! G2o')
    vim.cmd('stopinsert')
    vim.cmd(
      'normal! i@{grep_search} @{file_search} @{read_file} @{create_file}'
    )
    vim.cmd('normal! Go')
    vim.cmd('stopinsert')
    vim.cmd('normal! i@{insert_edit_into_file} @{web_search} @{fetch_webpage} ')
    vim.cmd('stopinsert')
  end

  local function open_new_chat_with_context_selection()
    if toggle_if_already_in_chat() then
      return
    end
    vim.cmd('CodeCompanionChat')
    vim.cmd('normal! gg}}{i#{buffer} #{diagnostics}')
    vim.cmd('normal! G2o')
    vim.cmd('stopinsert')
    vim.cmd(
      'normal! i@{grep_search} @{file_search} @{read_file} @{create_file}'
    )
    vim.cmd('normal! Go')
    vim.cmd('stopinsert')
    vim.cmd('normal! i@{insert_edit_into_file} @{web_search} @{fetch_webpage} ')
    vim.cmd('stopinsert')
  end

  local function toggle_chat_with_context_selection()
    if toggle_if_already_in_chat() then
      return
    end
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
      vim.cmd('normal! Go#{buffer} #{diagnostics}')
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
  helpers.ft_keymap_set_multi('codecompanion', {
    { 'n', '<leader>m', function() Lpke_cc_model({ 'son', 'opus', 'gpt' }) end, { desc = 'CodeCompanion: Cycle between AI models' }},
  })
  helpers.command_set_multi({
    { '*', 'Model', function(cmd)
      if #cmd.fargs == 0 then
        print(':Model <model1> [<model2>...] | eg: son|opus|gpt|gem|<exact>')
      else
        Lpke_cc_model(cmd.fargs)
      end
    end, { desc = 'CodeCompanion: Swap to (or between) models' } },
  })
  -- stylua: ignore end

  codecompanion.setup({
    adapters = {
      http = {
        copilot = function()
          return require('codecompanion.adapters').extend('copilot', {
            schema = {
              model = {
                default = 'claude-sonnet-4.6', -- premium requests (x1)
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
      }
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
          ["delete_file"] = {
            opts = {
              allowed_in_yolo_mode = true,
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
            modes = { n = 'q' },
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
              local approvals = require('codecompanion.interactions.chat.tools.approvals')
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
        slash_commands = {
          ['git_files'] = {
            description = 'List git files',
            callback = function(chat)
              local handle = io.popen('git ls-files')
              if handle ~= nil then
                local result = handle:read('*a')
                handle:close()
                chat:add_context(
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
        shared = {
          editor_context = {
            ['buffer'] = {
              opts = {
                default_params = 'diff',
              },
            },
          },
        }
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
