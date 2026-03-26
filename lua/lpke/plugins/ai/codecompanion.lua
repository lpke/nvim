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
        require('codecompanion.interactions.chat.tools.approvals'):toggle_yolo_mode(
          bufnr
        )
      end
    end,
  })

  local function open_new_chat_with_context()
    if toggle_if_already_in_chat() then
      return
    end
    vim.cmd('CodeCompanionChat')
    vim.cmd('normal! i#{buffer}')
    vim.cmd('normal! o#{diagnostics}')
    vim.cmd('normal! o')
    vim.cmd('normal! o@{agent}')
    vim.cmd('normal! o@{fetch_webpage}')
    vim.cmd('normal! o@{web_search}')
    vim.cmd('normal! G2o')
    vim.cmd('stopinsert')
  end

  local function open_new_chat_with_context_selection()
    if toggle_if_already_in_chat() then
      return
    end
    vim.cmd('CodeCompanionChat')
    vim.cmd('normal! gg}}{i#{buffer}')
    vim.cmd('normal! o#{diagnostics}')
    vim.cmd('normal! o')
    vim.cmd('normal! o@{agent}')
    vim.cmd('normal! o@{fetch_webpage}')
    vim.cmd('normal! o@{web_search}')
    vim.cmd('normal! o')
    vim.cmd('normal! G2o')
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
      vim.cmd('normal! o#{buffer}')
      vim.cmd('normal! o#{diagnostics}')
      vim.cmd('normal! o')
      vim.cmd('normal! o@{agent}')
      vim.cmd('normal! o@{fetch_webpage}')
      vim.cmd('normal! o@{web_search}')
      vim.cmd('normal! o')
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
    { 'n', '<leader>m', function() Lpke_cc_model({ 'son', 'opus', 'gpt' }) end,
      { desc = 'CodeCompanion: Cycle between AI models' }},
    { 'in', '<A-a>', function() vim.api.nvim_put({'@{agent} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert agent tool' }},
    { 'in', '<F2>a', function() vim.api.nvim_put({'@{agent} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert agent tool' }},
    { 'in', '<A-A>', function() vim.api.nvim_put({'@{agent} @{web_search} @{fetch_webpage} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert agent + web tools' }},
    { 'in', '<F2>A', function() vim.api.nvim_put({'@{agent} @{web_search} @{fetch_webpage} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert agent + web tools' }},
    { 'in', '<A-S>', function() vim.api.nvim_put({'@{web_search} @{fetch_webpage} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert web tools' }},
    { 'in', '<F2>S', function() vim.api.nvim_put({'@{web_search} @{fetch_webpage} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert web tools' }},
    { 'in', '<A-b>', function() vim.api.nvim_put({'#{buffer} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert buffer context' }},
    { 'in', '<F2>b', function() vim.api.nvim_put({'#{buffer} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert buffer context' }},
    { 'in', '<A-B>', function() vim.api.nvim_put({'#{buffers} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert all buffers context' }},
    { 'in', '<F2>B', function() vim.api.nvim_put({'#{buffers} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert all buffers context' }},
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
              require_approval_before = function(tool, tools)
                -- Only auto-approve commands when YOLO mode is enabled.
                -- Without YOLO mode, every command requires approval.
                local approvals =
                  require('codecompanion.interactions.chat.tools.approvals')
                if not approvals:is_approved(tools.bufnr) then
                  return true
                end

                local cmd = tool.args and tool.args.cmd or ''

                -- Unsafe patterns: always require approval, checked first.
                -- These match destructive, privilege-escalating, or
                -- system-altering commands even when embedded in pipes
                -- or subshells.
                local unsafe_patterns = {
                  -- file/directory destruction
                  'rm ',
                  'rm$',
                  'rmdir ',
                  'shred ',
                  'unlink ',
                  -- disk / filesystem
                  'mkfs',
                  'fdisk',
                  'dd ',
                  -- privilege escalation
                  'sudo ',
                  'su ',
                  'doas ',
                  'pkexec ',
                  -- package management (installs, removes, upgrades)
                  'apt ',
                  'apt%-get ',
                  'dpkg ',
                  'pacman ',
                  'yay ',
                  'paru ',
                  'dnf ',
                  'yum ',
                  'snap ',
                  'flatpak ',
                  'pip install',
                  'pip uninstall',
                  'pip3 install',
                  'pip3 uninstall',
                  'npm install %-g',
                  'npm i %-g',
                  'npm uninstall',
                  'cargo install',
                  -- system services / init
                  'systemctl ',
                  'service ',
                  'reboot',
                  'shutdown',
                  'poweroff',
                  'halt',
                  'init ',
                  -- networking / firewall
                  'iptables ',
                  'nft ',
                  'ufw ',
                  -- user / group management
                  'useradd',
                  'userdel',
                  'usermod',
                  'groupadd',
                  'groupdel',
                  'groupmod',
                  'passwd',
                  'chown ',
                  'chmod ',
                  -- writing to arbitrary files
                  'tee ',
                  'truncate ',
                  -- container / vm with host access
                  'docker run',
                  'podman run',
                  -- process manipulation
                  'kill ',
                  'killall ',
                  'pkill ',
                  -- shell eval / code execution from string
                  'eval ',
                  'bash %-c',
                  'sh %-c',
                  'zsh %-c',
                  -- cURL/wget that could POST or overwrite files
                  'curl %-X',
                  'curl %-%-request',
                  'curl %-d',
                  'curl %-%-data',
                  'curl .*|', -- piped curl output
                  'wget %-O',
                  'wget %-%-output',
                  -- git destructive operations
                  'git push %-%-force',
                  'git push %-f ',
                  'git reset %-%-hard',
                  'git clean %-fd',
                  'git clean %-f',
                  'git checkout %-%-',
                  -- misc dangerous
                  'mv / ', -- moving root
                  ':%!', -- vim external filter
                  'xargs ',
                }
                for _, pattern in ipairs(unsafe_patterns) do
                  if cmd:match(pattern) then
                    return true -- require approval
                  end
                end

                -- Safe patterns: auto-approve without prompting.
                -- Read-only, informational, or low-risk commands.
                local safe_patterns = {
                  -- filesystem browsing
                  '^ls',
                  '^exa ',
                  '^eza ',
                  '^tree ',
                  '^find ',
                  '^fd ',
                  '^stat ',
                  '^file ',
                  '^du ',
                  '^df ',
                  '^realpath ',
                  '^readlink ',
                  '^basename ',
                  '^dirname ',
                  -- reading files
                  '^cat ',
                  '^bat ',
                  '^head ',
                  '^tail ',
                  '^less ',
                  '^more ',
                  '^wc ',
                  '^md5sum ',
                  '^sha256sum ',
                  -- text search
                  '^grep ',
                  '^egrep ',
                  '^fgrep ',
                  '^rg ',
                  '^ag ',
                  '^awk ',
                  '^sed %-n',
                  -- output / formatting
                  '^echo ',
                  '^printf ',
                  '^date',
                  '^cal$',
                  '^cal ',
                  '^env$',
                  '^env ',
                  '^printenv',
                  '^pwd$',
                  '^whoami$',
                  '^id$',
                  '^id ',
                  '^hostname',
                  '^uname',
                  -- git read-only
                  '^git status',
                  '^git diff',
                  '^git log',
                  '^git show',
                  '^git branch',
                  '^git remote %-v',
                  '^git remote show',
                  '^git tag',
                  '^git stash list',
                  '^git ls%-files',
                  '^git ls%-tree',
                  '^git rev%-parse',
                  '^git describe',
                  '^git blame',
                  '^git shortlog',
                  -- build / test / lint (common project commands)
                  '^make ',
                  '^make$',
                  '^cargo test',
                  '^cargo check',
                  '^cargo clippy',
                  '^cargo build',
                  '^cargo fmt',
                  '^go test',
                  '^go vet',
                  '^go build',
                  '^go fmt',
                  '^python[23]? %-m pytest',
                  '^pytest',
                  '^python[23]? %-m unittest',
                  '^python[23]? %-c ',
                  '^npm test',
                  '^npm run ',
                  '^npx ',
                  '^yarn test',
                  '^yarn run ',
                  '^pnpm test',
                  '^pnpm run ',
                  '^bun test',
                  '^bun run ',
                  '^luacheck ',
                  '^selene ',
                  '^stylua %-%-check',
                  '^eslint ',
                  '^prettier %-%-check',
                  '^rubocop ',
                  '^rspec ',
                  -- misc safe utilities
                  '^which ',
                  '^whereis ',
                  '^type ',
                  '^man ',
                  '^help ',
                  '^sort ',
                  '^uniq ',
                  '^cut ',
                  '^tr ',
                  '^diff ',
                  '^comm ',
                  '^cmp ',
                  '^jq ',
                  '^yq ',
                  '^column ',
                  '^paste ',
                  '^seq ',
                  '^yes ',
                  '^true$',
                  '^false$',
                  '^nproc$',
                  '^free ',
                  '^uptime$',
                  '^lscpu',
                  '^lsblk',
                  '^lspci',
                  '^lsusb',
                }
                for _, pattern in ipairs(safe_patterns) do
                  if cmd:match(pattern) then
                    return false -- auto-approve
                  end
                end

                return true -- require approval for anything else
              end,
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
        slash_commands = {
          ['image'] = {
            opts = {
              dirs = {
                vim.fn.expand('~/Pictures'),
                vim.fn.expand('~/Screenshots'),
                vim.fn.expand('~/Downloads'),
                vim.fn.expand('~/Videos'),
              },
            },
          },
          ['git_files_list'] = {
            description = 'List git files (not their contents)',
            callback = function(chat)
              local handle = io.popen('git ls-files')
              if handle ~= nil then
                local result = handle:read('*a')
                handle:close()
                local file_count = #vim.split(vim.trim(result), '\n')
                chat:add_context(
                  { role = 'user', content = result },
                  'git',
                  '<git-files-list files="' .. file_count .. '" />'
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
          -- vibe-coded. Be careful...
          ['external_files'] = {
            description = 'Add an external directory as context (files outside cwd)',
            callback = function(chat)
              local function add_dir_context(dir)
                if not dir or dir == '' then
                  return
                end
                dir = vim.fn.expand(dir)
                dir = vim.fs.normalize(dir)
                if vim.fn.isdirectory(dir) ~= 1 then
                  return vim.notify(
                    'Not a valid directory: ' .. dir,
                    vim.log.levels.ERROR,
                    { title = 'CodeCompanion' }
                  )
                end
                -- list files in the directory (respecting .gitignore if in a git repo)
                local files_output
                local git_check = vim.fn.system(
                  'git -C '
                    .. vim.fn.shellescape(dir)
                    .. ' rev-parse --is-inside-work-tree 2>/dev/null'
                )
                if vim.v.shell_error == 0 and git_check:match('true') then
                  files_output = vim.fn.system(
                    'git -C ' .. vim.fn.shellescape(dir) .. ' ls-files'
                  )
                else
                  files_output = vim.fn.system(
                    'find '
                      .. vim.fn.shellescape(dir)
                      .. ' -type f -not -path "*/.*" | head -500'
                  )
                end
                local context_content = string.format(
                  'The user has given you access to an additional directory outside the current working directory.\n'
                    .. 'External directory: %s\n\n'
                    .. 'You can use absolute paths to read, edit, create, and search files in this directory.\n'
                    .. 'Files in this directory:\n```\n%s```',
                  dir,
                  files_output or '(could not list files)'
                )
                chat:add_context(
                  { role = 'user', content = context_content },
                  'directory',
                  '<external-files>' .. dir .. '</external-files>'
                )
                vim.notify(
                  'Added external directory: ' .. dir,
                  vim.log.levels.INFO,
                  { title = 'CodeCompanion' }
                )
              end

              local function pick_with_input()
                vim.ui.input(
                  { prompt = 'Directory path: ', completion = 'dir' },
                  add_dir_context
                )
              end

              local function pick_with_telescope()
                local actions = require('telescope.actions')
                local action_state = require('telescope.actions.state')
                local pickers = require('telescope.pickers')
                local finders = require('telescope.finders')
                local config_values = require('telescope.config').values

                local home = vim.fn.expand('~')
                pickers
                  .new({}, {
                    prompt_title = '/external_files - Select Directory',
                    cwd = home,
                    finder = finders.new_oneshot_job({
                      'fd',
                      '--type',
                      'd',
                      '--hidden',
                      '--exclude',
                      '.git',
                      '--exclude',
                      'node_modules',
                    }, { cwd = home }),
                    sorter = config_values.generic_sorter({}),
                    attach_mappings = function(prompt_bufnr)
                      actions.select_default:replace(function()
                        local entry = action_state.get_selected_entry()
                        actions.close(prompt_bufnr)
                        if entry then
                          local selected = vim.fs.joinpath(home, entry.value)
                          add_dir_context(selected)
                        end
                      end)
                      return true
                    end,
                  })
                  :find()
              end

              vim.ui.select(
                { 'Telescope picker', 'Absolute path input' },
                { prompt = '/external_files - Choose method:' },
                function(choice)
                  if choice == 'Telescope picker' then
                    pick_with_telescope()
                  elseif choice == 'Absolute path input' then
                    pick_with_input()
                  end
                end
              )
            end,
            opts = {
              contains_code = false,
            },
          },
          ['git_commit_logs'] = {
            description = 'Add recent git commit messages and metadata to context',
            callback = function(chat)
              vim.ui.input(
                { prompt = 'Number of commits (default 20): ' },
                function(input)
                  if input == nil then
                    return
                  end
                  local cleaned = vim.trim(input):gsub('^%((.-)%)$', '%1')
                  local count = tonumber(cleaned)
                  if not count or count < 1 then
                    count = 20
                  end
                  local cmd = string.format(
                    'git log -n %d --pretty=format:"%%h %%ai %%an %%d %%s"',
                    count
                  )
                  local handle = io.popen(cmd)
                  if not handle then
                    return vim.notify(
                      'Failed to run git log',
                      vim.log.levels.ERROR,
                      { title = 'CodeCompanion' }
                    )
                  end
                  local result = handle:read('*a')
                  handle:close()
                  if not result or result == '' then
                    return vim.notify(
                      'No git commits found',
                      vim.log.levels.INFO,
                      { title = 'CodeCompanion' }
                    )
                  end
                  local content = string.format(
                    'Recent git commits (last %d):\n```\n%s\n```',
                    count,
                    result
                  )
                  chat:add_context(
                    { role = 'user', content = content },
                    'git',
                    '<git-commit-logs commits="' .. count .. '" />'
                  )
                  vim.notify(
                    string.format('Added %d git commits to context', count),
                    vim.log.levels.INFO,
                    { title = 'CodeCompanion' }
                  )
                end
              )
            end,
            opts = {
              contains_code = false,
            },
          },
          ['git_commit_history'] = {
            description = 'Add full diffs for recent git commits',
            callback = function(chat)
              vim.ui.input(
                { prompt = 'Number of commits with diffs (default 5): ' },
                function(input)
                  if input == nil then
                    return
                  end
                  local cleaned =
                    vim.trim(input):gsub('^%((.-)%)$', '%1')
                  local count = tonumber(cleaned)
                  if not count or count < 1 then
                    count = 5
                  end

                  -- Get the last N commit hashes
                  local log_cmd = string.format(
                    'git log -n %d --pretty=format:"%%H"',
                    count
                  )
                  local log_handle = io.popen(log_cmd)
                  if not log_handle then
                    return vim.notify(
                      'Failed to run git log',
                      vim.log.levels.ERROR,
                      { title = 'CodeCompanion' }
                    )
                  end
                  local hashes_raw = log_handle:read('*a')
                  log_handle:close()
                  local hashes =
                    vim.split(vim.trim(hashes_raw), '\n')
                  if
                    #hashes == 0
                    or (hashes[1] == '' and #hashes == 1)
                  then
                    return vim.notify(
                      'No git commits found',
                      vim.log.levels.INFO,
                      { title = 'CodeCompanion' }
                    )
                  end

                  -- Build full diffs for each commit
                  local parts = {}
                  for i, hash in ipairs(hashes) do
                    -- Get commit metadata
                    local meta_cmd = string.format(
                      'git log -1 --pretty=format:"%%h %%ai %%an %%s" %s',
                      hash
                    )
                    local meta_handle = io.popen(meta_cmd)
                    local meta = meta_handle
                        and meta_handle:read('*a')
                      or ''
                    if meta_handle then
                      meta_handle:close()
                    end

                    -- Get full diff for this commit
                    local diff_cmd = string.format(
                      'git diff %s~1..%s 2>/dev/null',
                      hash,
                      hash
                    )
                    local diff_handle = io.popen(diff_cmd)
                    local diff = diff_handle
                        and diff_handle:read('*a')
                      or ''
                    if diff_handle then
                      diff_handle:close()
                    end

                    if diff == '' then
                      diff =
                        '(initial commit or no parent diff available)'
                    end

                    table.insert(
                      parts,
                      string.format(
                        '--- Commit %d: %s ---\n```diff\n%s\n```',
                        i,
                        vim.trim(meta),
                        vim.trim(diff)
                      )
                    )
                  end

                  local content = string.format(
                    'Git commit history with full diffs (last %d commits):\n\n%s',
                    #hashes,
                    table.concat(parts, '\n\n')
                  )
                  chat:add_context(
                    { role = 'user', content = content },
                    'git',
                    '<git-commit-history versions="'
                      .. #hashes
                      .. '" />'
                  )
                  vim.notify(
                    string.format(
                      'Added %d commits with diffs to context',
                      #hashes
                    ),
                    vim.log.levels.INFO,
                    { title = 'CodeCompanion' }
                  )
                end
              )
            end,
            opts = {
              contains_code = true,
            },
          },
          ['git_file_history'] = {
            description = 'Add git diffs for a file going back N versions',
            callback = function(chat)
              local actions = require('telescope.actions')
              local action_state = require('telescope.actions.state')
              local pickers = require('telescope.pickers')
              local finders = require('telescope.finders')
              local config_values = require('telescope.config').values

              -- Step 1: Pick a file using telescope (git ls-files)
              local handle = io.popen('git ls-files')
              if not handle then
                return vim.notify(
                  'Failed to list git files',
                  vim.log.levels.ERROR,
                  { title = 'CodeCompanion' }
                )
              end
              local files_raw = handle:read('*a')
              handle:close()
              local files = vim.split(vim.trim(files_raw), '\n')
              if #files == 0 or (files[1] == '' and #files == 1) then
                return vim.notify(
                  'No git-tracked files found',
                  vim.log.levels.INFO,
                  { title = 'CodeCompanion' }
                )
              end

              pickers
                .new({}, {
                  prompt_title = '/git_file_history - Select File',
                  finder = finders.new_table({ results = files }),
                  sorter = config_values.generic_sorter({}),
                  attach_mappings = function(prompt_bufnr)
                    actions.select_default:replace(function()
                      local entry = action_state.get_selected_entry()
                      actions.close(prompt_bufnr)
                      if not entry then
                        return
                      end
                      local selected_file = entry.value

                      -- Step 2: Ask how many versions back
                      vim.ui.input({
                        prompt = 'Versions back for "'
                          .. selected_file
                          .. '" (default 5): ',
                      }, function(input)
                        if input == nil then
                          return
                        end
                        local cleaned = vim.trim(input):gsub('^%((.-)%)$', '%1')
                        local count = tonumber(cleaned)
                        if not count or count < 1 then
                          count = 5
                        end

                        -- Get the last N commits that touched this file
                        local log_cmd = string.format(
                          'git log -n %d --pretty=format:"%%H" -- %s',
                          count,
                          vim.fn.shellescape(selected_file)
                        )
                        local log_handle = io.popen(log_cmd)
                        if not log_handle then
                          return vim.notify(
                            'Failed to get file history',
                            vim.log.levels.ERROR,
                            { title = 'CodeCompanion' }
                          )
                        end
                        local hashes_raw = log_handle:read('*a')
                        log_handle:close()
                        local hashes = vim.split(vim.trim(hashes_raw), '\n')
                        if
                          #hashes == 0
                          or (hashes[1] == '' and #hashes == 1)
                        then
                          return vim.notify(
                            'No history found for ' .. selected_file,
                            vim.log.levels.INFO,
                            { title = 'CodeCompanion' }
                          )
                        end

                        -- Build diffs for each commit
                        local parts = {}
                        for i, hash in ipairs(hashes) do
                          -- Get commit metadata
                          local meta_cmd = string.format(
                            'git log -1 --pretty=format:"%%h %%ai %%an %%s" %s',
                            hash
                          )
                          local meta_handle = io.popen(meta_cmd)
                          local meta = meta_handle and meta_handle:read('*a')
                            or ''
                          if meta_handle then
                            meta_handle:close()
                          end

                          -- Get diff for this commit
                          local diff_cmd = string.format(
                            'git diff %s~1..%s -- %s 2>/dev/null',
                            hash,
                            hash,
                            vim.fn.shellescape(selected_file)
                          )
                          local diff_handle = io.popen(diff_cmd)
                          local diff = diff_handle and diff_handle:read('*a')
                            or ''
                          if diff_handle then
                            diff_handle:close()
                          end

                          if diff == '' then
                            diff =
                              '(initial commit or no parent diff available)'
                          end

                          table.insert(
                            parts,
                            string.format(
                              '--- Version %d: %s ---\n```diff\n%s\n```',
                              i,
                              vim.trim(meta),
                              vim.trim(diff)
                            )
                          )
                        end

                        local content = string.format(
                          'Git file history for `%s` (last %d versions):\n\n%s',
                          selected_file,
                          #hashes,
                          table.concat(parts, '\n\n')
                        )
                        chat:add_context(
                          { role = 'user', content = content },
                          'git',
                          '<git-file-history versions="'
                            .. #hashes
                            .. '">'
                            .. selected_file
                            .. '</git-file-history>'
                        )
                        vim.notify(
                          string.format(
                            'Added %d versions of %s to context',
                            #hashes,
                            selected_file
                          ),
                          vim.log.levels.INFO,
                          { title = 'CodeCompanion' }
                        )
                      end)
                    end)
                    return true
                  end,
                })
                :find()
            end,
            opts = {
              contains_code = true,
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
