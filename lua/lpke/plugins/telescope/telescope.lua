local function config()
  local telescope = require('telescope')
  local actions = require('telescope.actions')
  local actions_state = require('telescope.actions.state')
  local actions_utils = require('telescope.actions.utils')
  local actions_layout = require('telescope.actions.layout')
  local builtin_pickers = require('telescope.builtin')
  local custom_pickers = require('lpke.plugins.telescope.custom_pickers')

  local smart_find_ai = require('lpke.plugins.telescope.smart_find_ai')
  local ts_helpers = require('lpke.plugins.telescope.helpers')

  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- stylua: ignore start
  -- theme
  helpers.set_hl_multi({
    ['TelescopeBorder'] = { fg = tc.surface, bg = tc.surface },
    ['TelescopePromptBorder'] = { fg = tc.overlaybump, bg = tc.overlaybump },
    ['TelescopePromptNormal'] = { fg = tc.text, bg = tc.overlaybump },
    ['TelescopePromptPrefix'] = { fg = tc.textminus, bg = tc.overlaybump },
    ['TelescopeSelectionCaret'] = { fg = tc.textminus, bg = tc.surface },
    ['TelescopeSelection'] = { fg = tc.text, bg = tc.overlaybump },
    ['TelescopeResultsTitle'] = { fg = tc.base, bg = tc.pine },
    ['TelescopePreviewTitle'] = { fg = tc.base, bg = tc.growth },
    ['TelescopePromptTitle'] = { fg = tc.base, bg = tc.iris },
    ['TelescopePromptCounter'] = { fg = tc.mutedplus, bg = tc.overlaybump },
    ['TelescopeMatching'] = { fg = tc.iris, bold = true },
    ['TelescopeResultsNormal'] = { fg = tc.subtle, bg = tc.surface },
    ['TelescopeResultsDiffChange'] = { fg = tc.rose },
    ['TelescopeResultsDiffAdd'] = { fg = tc.foam },
    ['TelescopeResultsDiffDelete'] = { fg = tc.love },
    ['TelescopeResultsDiffUntracked'] = { fg = tc.irisfaded },
    ['TelescopeMultiSelection'] = { fg = tc.gold },
    ['TelescopeMultiIcon'] = { fg = tc.goldfaded },
  })
  -- stylua: ignore end

  -- options
  telescope.setup({
    defaults = {
      initial_mode = 'normal',
      sorting_strategy = 'ascending',
      -- display
      winblend = 0,
      border = true,
      results_title = false,
      wrap_results = false,
      dynamic_preview_title = true,
      scroll_strategy = 'limit',
      layout_strategy = 'horizontal',
      prompt_prefix = ' ',
      entry_prefix = ' ',
      selection_caret = ' ',
      path_display = {
        'truncate',
      },
      layout_config = {
        prompt_position = 'top',
        horizontal = {
          height = 0.92,
          width = 0.85,
          preview_width = 0.5,
        },
      },
      vimgrep_arguments = {
        'rg',
        '--follow', -- follow symbolic links
        '--hidden', -- search for hidden files
        '--no-heading', -- don't group matches by each file
        '--with-filename', -- filepath with matched lines
        '--line-number', -- show line numbers
        '--column', -- show column numbers
        '--smart-case',
        '--color=never',
        -- exclude:
        '--glob=!**/node_modules/*',
        '--glob=!**/.git/*',
        '--glob=!**/.idea/*',
        '--glob=!**/.vscode/*',
        '--glob=!**/.vercel/*',
        '--glob=!**/.next/*',
        '--glob=!**/build/*',
        '--glob=!**/dist/*',
        '--glob=!**/pnpm-lock.yaml',
        '--glob=!**/yarn.lock',
        '--glob=!**/package-lock.json',
        '--glob=!**/lazy-lock.json',
      },

      mappings = {
        i = {
          -- OPENING FILES
          ['<CR>'] = actions.select_default,
          ['<F2>.'] = actions.file_vsplit,
          ['<A-.>'] = actions.file_vsplit,
          ['<F2>,'] = actions.file_split,
          ['<A-,>'] = actions.file_split,
          ['<F2>n'] = actions.file_tab,
          ['<A-n>'] = actions.file_tab,

          -- RESULTS NAVIGATION
          ['<C-d>'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_next, bufnr, 10)
          end,
          ['<C-u>'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_previous, bufnr, 10)
          end,

          -- PREVIEW SCROLLING
          ['<C-j>'] = actions.preview_scrolling_down,
          ['<C-k>'] = actions.preview_scrolling_up,
          -- ['<C-h>'] = actions.preview_scrolling_left,
          -- ['<C-l>'] = actions.preview_scrolling_right,
          ['<F2>p'] = actions_layout.toggle_preview,
          ['<A-p>'] = actions_layout.toggle_preview,

          -- SELECTIONS
          ['<Tab>'] = function(bufnr)
            actions.toggle_selection(bufnr)
            actions.move_selection_next(bufnr)
          end,
          ['<S-Tab>'] = function(bufnr)
            actions.toggle_selection(bufnr)
            actions.move_selection_previous(bufnr)
          end,
          ['<C-v>'] = actions.toggle_all,

          -- QUICKFIX LIST
          ['<C-q>'] = function(bufnr)
            actions.smart_send_to_qflist(bufnr)
            builtin_pickers.quickfix()
          end,
        },
        n = {
          -- HACKS/FIXES
          ['u'] = function(bufnr)
            local num_selected = 0
            actions_utils.map_selections(bufnr, function(_)
              num_selected = num_selected + 1
            end)
            if num_selected > 0 then
              actions.drop_all(bufnr)
            else
              vim.cmd('undo')
            end
          end,
          ['p'] = function()
            vim.api.nvim_paste(vim.fn.getreg('0'), false, -1)
            -- not sure why this message appears when pasting in telescope, but
            -- I don't want to see it!
            helpers.clear_last_message('Content is not an image.')
          end,

          -- OPENING FILES
          ['<CR>'] = actions.select_default,
          ['<F2>.'] = actions.file_vsplit,
          ['<A-.>'] = actions.file_vsplit,
          ['<F2>,'] = actions.file_split,
          ['<A-,>'] = actions.file_split,
          ['<F2>n'] = actions.file_tab,
          ['<A-n>'] = actions.file_tab,

          -- SEARCHING
          ['/'] = { 'i', type = 'command' },

          -- RESULTS MOVEMENT
          ['<Down>'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_next, bufnr, 4)
          end,
          ['<Up>'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_previous, bufnr, 4)
          end,
          ['J'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_next, bufnr, 20)
          end,
          ['K'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_previous, bufnr, 20)
          end,
          ['<C-d>'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_next, bufnr, 10)
          end,
          ['<C-u>'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_previous, bufnr, 10)
          end,

          -- PREVIEW SCROLLING
          ['<C-j>'] = actions.preview_scrolling_down,
          ['<C-k>'] = actions.preview_scrolling_up,
          -- ['<C-h>'] = actions.preview_scrolling_left, -- uncomment when released
          -- ['<C-l>'] = actions.preview_scrolling_right, -- uncomment when released

          -- LAYOUT CONTROL
          ['<F2>p'] = actions_layout.toggle_preview,
          ['<A-p>'] = actions_layout.toggle_preview,
          ['<F2>O'] = actions_layout.toggle_mirror,
          ['<A-O>'] = actions_layout.toggle_mirror,

          -- SELECTIONS
          ['<Tab>'] = function(bufnr)
            actions.toggle_selection(bufnr)
            actions.move_selection_next(bufnr)
          end,
          ['<S-Tab>'] = function(bufnr)
            actions.toggle_selection(bufnr)
            actions.move_selection_previous(bufnr)
          end,
          ['v'] = function(bufnr)
            actions.toggle_all(bufnr)
            helpers.refresh_picker(bufnr)
          end,
          ['V'] = actions.select_all,

          -- QUICKFIX LIST
          ['q'] = function(bufnr)
            actions.smart_send_to_qflist(bufnr)
            builtin_pickers.quickfix()
          end,
          ['QF'] = function(bufnr)
            actions.smart_add_to_qflist(bufnr)
            builtin_pickers.quickfix()
          end,
          ['h'] = function(bufnr) -- handle 'up a level' actions if cant be done in picker-scope
            local prompt_title =
              actions_state.get_current_picker(bufnr).prompt_title
            if prompt_title == 'Quickfix' then -- open quickfixhistory
              builtin_pickers.quickfixhistory()
            else
              vim.api.nvim_feedkeys(
                vim.api.nvim_replace_termcodes('h', true, false, true),
                'n',
                false
              )
            end
          end,

          -- DELETE
          ['dD'] = function(bufnr) -- handle 'delete' actions if cant be done in picker-scope
            local prompt_title =
              actions_state.get_current_picker(bufnr).prompt_title
            if prompt_title == 'Sessions' then -- delete session
              ts_helpers.delete_session(bufnr)
            elseif prompt_title == 'Quickfix' then -- remove qflist items
              ts_helpers.remove_selected_from_qflist(bufnr)
            elseif prompt_title == 'harpoon marks' then -- remove harpoon
              ts_helpers.remove_selected_from_harpoon(bufnr)
            elseif prompt_title == 'Saved Chats' then -- remove harpoon
              ts_helpers.remove_selected_from_codecompanion(bufnr)
            end
          end,
        },
      },
    },

    pickers = {
      resume = {
        initial_mode = 'normal',
      },
      find_files = {
        initial_mode = 'insert',
        sorting_strategy = 'ascending',
        hidden = true,
        -- needed to exclude some files & dirs from general search
        -- when not included or specified in .gitignore
        find_command = {
          'rg',
          '--files',
          '--hidden',
          -- exclude:
          '--glob=!**/node_modules/*',
          '--glob=!**/.git/*',
          '--glob=!**/.idea/*',
          '--glob=!**/.vscode/*',
          '--glob=!**/.vercel/*',
          '--glob=!**/.next/*',
          '--glob=!**/build/*',
          '--glob=!**/dist/*',
          '--glob=!**/pnpm-lock.yaml',
          '--glob=!**/yarn.lock',
          '--glob=!**/package-lock.json',
        },
      },
      live_grep = {
        initial_mode = 'insert',
        sorting_strategy = 'ascending',
      },
      current_buffer_fuzzy_find = {
        initial_mode = 'insert',
        sorting_strategy = 'ascending',
      },
      git_commits = {
        git_command = {
          'git',
          'log',
          '--pretty=tformat:%h %ad  %s',
          '--date=format:%y-%m-%d %H:%M',
          '--abbrev-commit',
          '--',
          '.',
        },
      },
      git_bcommits = {
        prompt_title = 'File Commits',
        git_command = {
          'git',
          'log',
          '--pretty=tformat:%h %ad  %s',
          '--date=format:%y-%m-%d %H:%M',
          '--abbrev-commit',
        },
      },
      git_bcommits_range = {
        git_command = {
          'git',
          'log',
          '--pretty=tformat:%h %ad  %s',
          '--date=format:%y-%m-%d %H:%M',
          '--abbrev-commit',
          '--no-patch',
          '-L',
        },
      },
      buffers = {
        mappings = {
          n = {
            ['dD'] = actions.delete_buffer,
            ['dxD'] = ts_helpers.force_delete_selected_bufs,
            ['dX'] = function()
              Lpke_clean_buffers()
              builtin_pickers.buffers()
            end,
          },
        },
      },
      quickfix = {
        mappings = {
          n = {
            ['q'] = function(bufnr)
              actions.close(bufnr)
              vim.cmd('botright copen')
            end,
            ['h'] = function()
              builtin_pickers.quickfixhistory()
            end,
            ['dD'] = ts_helpers.remove_selected_from_qflist,
          },
        },
      },
      quickfixhistory = {
        mappings = {
          n = {
            ['q'] = function(bufnr)
              actions.close(bufnr)
              vim.cmd('botright copen')
            end,
            ['l'] = actions.select_default,
          },
        },
      },
      registers = {
        initial_mode = 'insert',
        sorting_strategy = 'ascending',
      },
      keymaps = {
        initial_mode = 'insert',
        sorting_strategy = 'ascending',
      },
      highlights = {
        initial_mode = 'insert',
        sorting_strategy = 'ascending',
      },
      help_tags = {
        initial_mode = 'insert',
        sorting_strategy = 'ascending',
      },
    },

    extensions = {},
  })

  -- extensions
  telescope.load_extension('fzf')
  telescope.load_extension('harpoon')

  -- stylua: ignore start
  -- mappings to access telescope
  helpers.keymap_set_multi({
    {'n', '<BS><leader>', function()
      builtin_pickers.resume()
    end, { desc = 'Resume previous Telescope search' }},

    -- files
    {'n', '<BS><BS>', function()
      -- builtin_pickers.find_files()
      -- TODO: tidy this up. Original implementation above
      smart_find_ai.smart_find()
    end, { desc = 'Find files in cwd (or directories in oil)' }},
    -- TEMP:
    {'n', '<BS>fd', function()
      custom_pickers.find_dirs()
    end, { desc = 'Find directories in cwd' }},
    {'n', '<BS>ff', function()
      if Lpke_find_git_root(vim.fn.getcwd(-1, -1)) then
        builtin_pickers.git_files()
      else
        builtin_pickers.find_files()
      end
    end, { desc = 'Find git files in cwd (or cwd if not git)' }},
    {'n', '<BS>fr', function()
      builtin_pickers.oldfiles({ prompt_title = 'Recent Files' })
    end, { desc = 'Find recent files' }},

    -- grep
    {'n', '<leader>/', function()
      builtin_pickers.current_buffer_fuzzy_find({ prompt_title = 'Find in Buffer' })
    end, { desc = 'Find in current file' }},
    {'n', '<BS>/', function()
      custom_pickers.live_multigrep({ prompt_title = 'Find in Files' })
    end, { desc = 'Find string in cwd, with file filtering (str  filter)' } },
    {'n', '<BS>fp', function()
      builtin_pickers.grep_string({ search = vim.fn.getreg('"') })
    end, { desc = 'Find pasted string in cwd' } },
    {'n', '<BS>fi', function()
      builtin_pickers.grep_string({ search = vim.fn.input('Grep: ') })
    end, { desc = 'Find input string in cwd' } },
    {'n', '<BS>fw', function()
      builtin_pickers.grep_string()
    end, { desc = 'Find string under cursor in cwd' }},

    -- git
    {'n', '<BS>gb', function()
      builtin_pickers.git_branches()
    end, { desc = 'Find git branches' }},
    -- using diffview.nvim to do the below now
    -- {'n', '<BS>gg', function()
    --   builtin_pickers.git_status()
    -- end, { desc = 'Find git status' }},
    -- {'n', '<BS>gc', function()
    --   builtin_pickers.git_commits()
    -- end, { desc = 'Find git commits' }},
    -- {'n', '<leader>gc', function()
    --   builtin_pickers.git_bcommits()
    -- end, { desc = 'Find buffer git commits' }},
    -- {'v', '<leader>gc', function()
    --   vim.cmd('normal! \28\14') -- go to normal - saves prev selection `<`/`>` marks
    --   local start_line = vim.api.nvim_buf_get_mark(0, "<")[1]
    --   local end_line = vim.api.nvim_buf_get_mark(0, ">")[1]
    --   builtin_pickers.git_bcommits_range({
    --     prompt_title = 'File Commits (L' .. start_line .. '-' .. end_line .. ')',
    --     from = start_line, to = end_line
    --   })
    -- end, { desc = 'Find selection git commits' }},
    -- {'n', '<BS>gs', function()
    --   builtin_pickers.git_stash()
    -- end, { desc = 'Find git stash' }},

    -- treesitter
    {'n', '<leader>fs', function()
      builtin_pickers.treesitter()
    end, { desc = 'Find treesitter symbols in file' }},

    -- vim
    {'n', '<BS>fb', function()
      builtin_pickers.buffers()
    end, { desc = 'Find buffers' } },
    {'n', '<BS>l', function()
      builtin_pickers.quickfix()
    end, { desc = 'Open quickfix list' } },
    {'n', '<BS>fm', function()
      builtin_pickers.marks()
    end, { desc = 'Find marks' } },
    {'n', "<BS>f'", function()
      builtin_pickers.registers()
    end, { desc = 'Find registers' }},
    {'n', '<BS>fj', function()
      builtin_pickers.jumplist()
    end, { desc = 'Find jumplist' } },
    {'n', '<BS>fk', function()
      builtin_pickers.keymaps()
    end, { desc = 'Find keymaps' } },
    {'n', '<BS>fl', function()
      builtin_pickers.highlights()
    end, { desc = 'Find highlights' }},
    {'n', '<BS>fh', function()
      builtin_pickers.help_tags()
    end, { desc = 'Find help tags' }},
  })
  -- stylua: ignore end
end

return {
  'nvim-telescope/telescope.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    -- improves sorting performance (as per docs):
    { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
  },
  config = config,
}
