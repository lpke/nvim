local function config()
  local telescope = require('telescope')
  local actions = require('telescope.actions')
  local actions_state = require('telescope.actions.state')
  local actions_utils = require('telescope.actions.utils')
  local actions_layout = require('telescope.actions.layout')
  local builtin = require('telescope.builtin')

  local fb_actions = require('telescope._extensions.file_browser.actions')
  local fb_settings =
    require('lpke.plugins.telescope-file-browser').telescope_settings

  local session_actions = require('auto-session.session-lens.actions')

  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- stylua: ignore start
  -- theme
  helpers.set_hl('TelescopeBorder', { fg = tc.surface, bg = tc.surface })
  helpers.set_hl('TelescopePromptBorder', { fg = tc.overlaybump, bg = tc.overlaybump })
  helpers.set_hl('TelescopePromptNormal', { fg = tc.text, bg = tc.overlaybump })
  helpers.set_hl('TelescopePromptPrefix', { fg = tc.textminus, bg = tc.overlaybump })
  helpers.set_hl('TelescopeSelectionCaret', { fg = tc.textminus, bg = tc.surface })
  helpers.set_hl('TelescopeSelection', { fg = tc.text, bg = tc.overlaybump })
  helpers.set_hl('TelescopeResultsTitle', { fg = tc.base, bg = tc.pine })
  helpers.set_hl('TelescopePreviewTitle', { fg = tc.base, bg = tc.growth })
  helpers.set_hl('TelescopePromptTitle', { fg = tc.base, bg = tc.iris })
  helpers.set_hl('TelescopePromptCounter', { fg = tc.mutedplus, bg = tc.overlaybump })
  helpers.set_hl('TelescopeMatching', { fg = tc.iris, bold = true })
  helpers.set_hl('TelescopeResultsDiffChange', { fg = tc.rose })
  helpers.set_hl('TelescopeResultsDiffAdd', { fg = tc.foam })
  helpers.set_hl('TelescopeResultsDiffDelete', { fg = tc.love })
  helpers.set_hl('TelescopeResultsDiffUntracked', { fg = tc.irisfaded })
  helpers.set_hl('TelescopeMultiSelection', { fg = tc.gold })
  helpers.set_hl('TelescopeMultiIcon', { fg = tc.goldfaded })
  -- stylua: ignore end

  -- custom pickers
  local function find_git_files()
    if helpers.cwd_has_git() then
      builtin.git_files()
    else
      builtin.find_files()
    end
  end
  local function grep_yanked()
    builtin.grep_string({ search = vim.fn.getreg('"') })
  end
  local function grep_custom()
    builtin.grep_string({ search = vim.fn.input('Grep: ') })
  end

  -- stylua: ignore start
  -- mappings to access telescope
  helpers.keymap_set_multi({
    {'nC', '<BS><leader>', 'Telescope resume', { desc = 'Resume previous Telescope search' }},
    -- files
    {'nC', '<BS><BS>', 'Telescope find_files', { desc = 'Fuzzy find files in cwd' }},
    {'n', '<BS>ff', find_git_files, { desc = 'Fuzzy find git files in cwd (or cwd if not git)' }},
    {'nC', '<BS>fr', 'Telescope oldfiles', { desc = 'Fuzzy find recent files' }},
    -- grep
    {'nC', '<leader>/', 'Telescope current_buffer_fuzzy_find', { desc = 'Fuzzy find in current file' }},
    {'nC', '<BS>/', 'Telescope live_grep', { desc = 'Find string in cwd' } },
    {'n', '<BS>fp', grep_yanked, { desc = 'Find pasted string in cwd' } },
    {'n', '<BS>fi', grep_custom, { desc = 'Find input string in cwd' } },
    {'nC', '<BS>fw', 'Telescope grep_string', { desc = 'Find string under cursor in cwd' }},
    -- git
    {'nC', '<BS>gg', 'Telescope git_status', { desc = 'Fuzzy find git status' }},
    {'nC', '<leader>gc', 'Telescope git_bcommits', { desc = 'Fuzzy find buffer git commits' }},
    {'nC', '<BS>gc', 'Telescope git_commits', { desc = 'Fuzzy find git commits' }},
    {'nC', '<BS>gb', 'Telescope git_branches', { desc = 'Fuzzy find git branches' }},
    {'nC', '<BS>gs', 'Telescope git_stash', { desc = 'Fuzzy find git stash' }},
    -- treesitter
    {'nC', '<leader>fs', 'Telescope treesitter', { desc = 'Fuzzy find treesitter symbols in file' }},
    -- vim
    {'nC', '<BS>fb', 'Telescope buffers', { desc = 'Fuzzy find buffers' } },
    {'nC', '<BS>l', 'Telescope quickfix', { desc = 'Open quickfix list' } },
    {'nC', '<BS>L', 'Telescope quickfixhistory', { desc = 'Open quickfix list history' } },
    {'nC', '<BS>fm', 'Telescope marks', { desc = 'Fuzzy find marks' } },
    {'nC', "<BS>f'", 'Telescope registers', { desc = 'Fuzzy find registers' }},
    {'nC', '<BS>fj', 'Telescope jumplist', { desc = 'Fuzzy find jumplist' } },
    {'nC', '<BS>fk', 'Telescope keymaps', { desc = 'Fuzzy find keymaps' } },
    {'nC', '<BS>fl', 'Telescope highlights', { desc = 'Fuzzy find highlights' }},
    {'nC', '<BS>fh', 'Telescope help_tags', { desc = 'Fuzzy find help tags' }},
  })
  -- stylua: ignore end

  -- options
  telescope.setup({
    defaults = {
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
        horizontal = {
          height = 0.92,
          width = 0.85,
          preview_width = 0.55,
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
          ['<F2>,'] = actions.file_split,
          ['<F2>n'] = actions.file_tab,

          -- RESULTS NAVIGATION
          ['<C-j>'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_next, bufnr, 8)
          end,
          ['<C-k>'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_previous, bufnr, 8)
          end,

          -- PREVIEW SCROLLING
          ['<C-d>'] = actions.preview_scrolling_down,
          ['<C-u>'] = actions.preview_scrolling_up,
          -- ['<C-h>'] = actions.preview_scrolling_left,
          -- ['<C-l>'] = actions.preview_scrolling_right,
          ['<F2>o'] = actions_layout.toggle_preview,

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
          ['<C-q>'] = actions.smart_add_to_qflist,
        },
        n = {
          -- HACKS/FIXES
          ['u'] = { '<cmd>undo<cr>', type = 'command' }, -- didn't work by default

          -- OPENING FILES
          ['<CR>'] = actions.select_default,
          ['<F2>.'] = actions.file_vsplit,
          ['<F2>,'] = actions.file_split,
          ['<F2>n'] = actions.file_tab,

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

          -- PREVIEW SCROLLING
          ['<C-d>'] = actions.preview_scrolling_down,
          ['<C-u>'] = actions.preview_scrolling_up,
          ['<C-j>'] = actions.preview_scrolling_down,
          ['<C-k>'] = actions.preview_scrolling_up,
          -- ['<C-h>'] = actions.preview_scrolling_left, -- uncomment when released
          -- ['<C-l>'] = actions.preview_scrolling_right, -- uncomment when released

          -- LAYOUT CONTROL
          ['<F2>o'] = actions_layout.toggle_preview,
          ['<F2>O'] = actions_layout.toggle_mirror,

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
            fb_actions.toggle_all(bufnr)
            helpers.refresh_picker(bufnr)
          end,
          ['V'] = actions.select_all,
          ['uv'] = actions.drop_all,

          -- QUICKFIX LIST
          ['q'] = actions.smart_add_to_qflist,
          ['Q'] = actions.smart_send_to_qflist,

          -- DELETE
          ['dD'] = function(bufnr) -- handle 'delete' actions if cant be done in picker-scope
            local picker = actions_state.get_current_picker(bufnr)
            if picker.prompt_title == 'Sessions' then -- delete session
              session_actions.delete_session(bufnr)
            end
          end,

          -- SUB-PICKER SEARCHING
          ['<BS><BS>'] = function(bufnr) -- find files (current path)
            local picker = actions_state.get_current_picker(bufnr)
            local path = picker.finder.path
            if path then
              print(path)
              vim.cmd('Telescope find_files cwd=' .. path)
            end
          end,
          ['<BS>/'] = function(bufnr) -- live grep (current path)
            local picker = actions_state.get_current_picker(bufnr)
            local path = picker.finder.path
            if path then
              print(path)
              vim.cmd('Telescope live_grep cwd=' .. path)
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
      git_status = {
        initial_mode = 'normal',
        sorting_strategy = 'ascending',
      },
      git_bcommits = {
        initial_mode = 'normal',
        sorting_strategy = 'ascending',
        prompt_title = 'File Commits',
      },
      git_commits = {
        initial_mode = 'normal',
        sorting_strategy = 'ascending',
      },
      git_branches = {
        initial_mode = 'normal',
        sorting_strategy = 'ascending',
      },
      git_stash = {
        initial_mode = 'normal',
        sorting_strategy = 'ascending',
      },
      treesitter = {
        initial_mode = 'normal',
        sorting_strategy = 'ascending',
      },
      buffers = {
        initial_mode = 'normal',
        mappings = {
          n = {
            ['dD'] = actions.delete_buffer,
          },
        },
      },
      marks = {
        initial_mode = 'normal',
        sorting_strategy = 'ascending',
      },
      jumplist = {
        initial_mode = 'normal',
        sorting_strategy = 'ascending',
      },
    },

    extensions = {
      -- :h telescope-file-browser.picker
      file_browser = fb_settings(
        fb_actions,
        actions,
        actions_state,
        actions_utils
      ),
    },
  })

  -- extensions
  telescope.load_extension('session-lens')
  telescope.load_extension('fzf')
  telescope.load_extension('file_browser')
end

return {
  'nvim-telescope/telescope.nvim',
  tag = '0.1.4',
  dependencies = {
    'nvim-lua/plenary.nvim',
    -- improves sorting performance (as per docs):
    { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
  },
  config = config,
}
