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
  local ignore = require('lpke.plugins.telescope.ignore')

  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  local function plugin_files_cwd()
    return vim.fs.joinpath(vim.fn.stdpath('data'), 'lazy')
  end

  local function live_literal_grep(default_text, prompt_title)
    custom_pickers.live_multigrep({
      prompt_title = prompt_title,
      default_text = default_text,
      fixed_strings = true,
    })
  end

  local function toggle_preview_wrap(bufnr)
    local preview_win = actions_state.get_current_picker(bufnr).preview_win
    if preview_win and vim.api.nvim_win_is_valid(preview_win) then
      vim.wo[preview_win].wrap = not vim.wo[preview_win].wrap
    end
  end

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
      vimgrep_arguments = ignore.vimgrep_arguments(),

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
          ['<A-w>'] = toggle_preview_wrap,

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
          ['<A-w>'] = toggle_preview_wrap,
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
            local prompt_title =
              actions_state.get_current_picker(bufnr).prompt_title
            actions.toggle_all(bufnr)
            if not prompt_title:match('^Saved Chats') then
              ts_helpers.refresh_picker(bufnr)
            end
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
              Lpke_feedkeys({ 'h', true, false }, 'n')
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
            elseif prompt_title:match('^Saved Chats') then -- delete saved chat
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
        find_command = ignore.rg_files_command(),
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
      -- TODO: tidy this up. Original implementation above
      smart_find_ai.smart_find()
    end, { desc = 'Find files in cwd (or directories in oil)' }},
    {'n', '<leader><BS><BS>', function()
      smart_find_ai.smart_find({ default_text = '@~  ' })
    end, { desc = 'Find files from home (or directories in oil)' }},
    {'n', '<BS>fd', function()
      smart_find_ai.find_directories()
    end, { desc = 'Find directories in cwd' }},
    {'n', '<BS>ff', function()
      smart_find_ai.find_files()
    end, { desc = 'Find files in cwd' }},
    {'n', '<BS>fr', function()
      builtin_pickers.oldfiles({ prompt_title = 'Recent Files' })
    end, { desc = 'Find recent files' }},
    {'n', '<BS>fs', function()
      custom_pickers.snippets()
    end, { desc = 'Find LuaSnip snippets' }},

    -- grep
    {'n', '<leader>/', function()
      builtin_pickers.current_buffer_fuzzy_find({ prompt_title = 'Find in Buffer' })
    end, { desc = 'Find in current file' }},
    {'n', '<BS>/', function()
      custom_pickers.live_multigrep({ prompt_title = 'Find in Files' })
    end, { desc = 'Find string in cwd, with file filtering (str  filter)' } },
    {'n', '<leader><BS>/', function()
      custom_pickers.live_multigrep({ prompt_title = 'Find in Files', default_text = '@~  ' })
    end, { desc = 'Find string from home, with file filtering (str  filter)' } },
    {'n', '<BS>fp', function()
      live_literal_grep(vim.fn.getreg('"'), 'Find Pasted String')
    end, { desc = 'Find pasted string in cwd' } },
    {'n', '<BS>fi', function()
      live_literal_grep(vim.fn.input('Grep: '), 'Find Input String')
    end, { desc = 'Find input string in cwd' } },
    {'n', '<BS>fw', function()
      live_literal_grep(vim.fn.expand('<cword>'), 'Find Word Under Cursor')
    end, { desc = 'Find string under cursor in cwd' }},
    {'n', '<BS>p<BS>', function()
      smart_find_ai.find_files({
        prompt_title = 'Find Plugin Files',
        cwd = plugin_files_cwd(),
      })
    end, { desc = 'Find plugin files' }},
    {'n', '<BS>p/', function()
      custom_pickers.live_multigrep({
        prompt_title = 'Find in Plugin Files',
        cwd = plugin_files_cwd(),
      })
    end, { desc = 'Find string in plugin files, with file filtering (str  filter)' }},

    -- git
    {'n', '<BS>gb', function()
      builtin_pickers.git_branches()
    end, { desc = 'Find git branches' }},
    {'n', '<BS>gg', function()
      builtin_pickers.git_status()
    end, { desc = 'Find git status' }},
    -- using diffview.nvim to do the below now
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
    {'n', '<BS>fc', function()
      custom_pickers.changelist()
    end, { desc = 'Find changelist' } },
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
  commit = 'b4da76be54691e854d3e0e02c36b0245f945c2c7',
  dependencies = {
    {
      'nvim-lua/plenary.nvim',
      commit = 'b9fd5226c2f76c951fc8ed5923d85e4de065e509',
    },
    -- improves sorting performance (as per docs):
    {
      'nvim-telescope/telescope-fzf-native.nvim',
      commit = '1f08ed60cafc8f6168b72b80be2b2ea149813e55',
      build = 'make',
    },
  },
  config = config,
}
