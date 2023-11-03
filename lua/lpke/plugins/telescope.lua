local function config()
  local telescope = require('telescope')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local action_utils = require('telescope.actions.utils')
  local fb_actions = require('telescope._extensions.file_browser.actions')
  local builtin = require('telescope.builtin')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- stylua: ignore start
  -- theme
  helpers.set_hl('TelescopeBorder', { fg = tc.surface, bg = tc.surface })
  helpers.set_hl( 'TelescopePromptBorder', { fg = tc.overlaybump, bg = tc.overlaybump })
  helpers.set_hl('TelescopePromptNormal', { fg = tc.text, bg = tc.overlaybump })
  helpers.set_hl( 'TelescopePromptPrefix', { fg = tc.textminus, bg = tc.overlaybump })
  helpers.set_hl( 'TelescopeSelectionCaret', { fg = tc.textminus, bg = tc.surface })
  helpers.set_hl('TelescopeSelection', { fg = tc.text, bg = tc.overlaybump })
  helpers.set_hl('TelescopeResultsTitle', { fg = tc.base, bg = tc.pine })
  helpers.set_hl('TelescopePreviewTitle', { fg = tc.base, bg = tc.growth })
  helpers.set_hl('TelescopePromptTitle', { fg = tc.base, bg = tc.iris })
  helpers.set_hl( 'TelescopePromptCounter', { fg = tc.mutedplus, bg = tc.overlaybump })
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
    builtin.grep_string({ search = vim.fn.input('Grep > ') })
  end

  -- stylua: ignore start
  -- mappings to access telescope
  helpers.keymap_set_multi({
    {'nC', '<BS><BS>', 'Telescope find_files', { desc = 'Fuzzy find files in cwd' }},
    {'n', '<BS>ff', find_git_files, { desc = 'Fuzzy find git files in cwd (or cwd if not git)' }},
    {'nC', '<BS>/', 'Telescope live_grep', { desc = 'Find string in cwd' } },
    {'nC', '<leader>/', 'Telescope current_buffer_fuzzy_find', { desc = 'Fuzzy find in current file' }},
    {'n', '<BS>fp', grep_yanked, { desc = 'Find pasted string in cwd' } },
    {'n', '<BS>fi', grep_custom, { desc = 'Find input string in cwd' } },
    {'nC', '<BS>fw', 'Telescope grep_string', { desc = 'Find string under cursor in cwd' }},
    {'nC', '<BS><leader>', 'Telescope resume initial_mode=normal', { desc = 'Resume previous Telescope search' }},
    {'nC', '<BS>fr', 'Telescope oldfiles', { desc = 'Fuzzy find recent files' }},
    {'nC', '<BS>fj', 'Telescope jumplist', { desc = 'Fuzzy find jumplist' } },
    {'nC', '<BS>fb', 'Telescope buffers', { desc = 'Fuzzy find buffers' } },
    {'nC', "<BS>f'", 'Telescope registers', { desc = 'Fuzzy find registers' }},
    {'nC', '<BS>fm', 'Telescope marks', { desc = 'Fuzzy find marks' } },
    {'nC', '<BS>fl', 'Telescope highlights', { desc = 'Fuzzy find highlights' }},
    {'nC', '<BS>fk', 'Telescope keymaps', { desc = 'Fuzzy find keymaps' } },
    {'nC', '<BS>fh', 'Telescope help_tags', { desc = 'Fuzzy find help tags' }},
    {'nC', '<BS>fs', 'Telescope treesitter', { desc = 'Fuzzy find treesitter symbols' }},
    {'nC', '<BS>fgc', 'Telescope git_commits', { desc = 'Fuzzy find git commits' }},
    {'nC', '<BS>fgf', 'Telescope git_bcommits', { desc = 'Fuzzy find buffer git commits' }},
    {'nC', '<BS>fgb', 'Telescope git_branches', { desc = 'Fuzzy find git branches' }},
    {'nC', '<BS>fgs', 'Telescope git_status', { desc = 'Fuzzy find git status' }},
    {'nC', '<BS>fgz', 'Telescope git_stash', { desc = 'Fuzzy find git stash' }},
    {'nC', '<BS>d', 'Telescope file_browser path=%:p:h select_buffer=true',
      { desc = 'Open Telescope File Browser' }},
    {'nC', '<BS>D', [[Telescope file_browser prompt_title=File\ Browser\ (depth:\ 5) path=%:p:h select_buffer=true depth=5 hidden=false]],
      { desc = 'Open Telescope File Browser (depth: 5)' }},
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
          ['<CR>'] = actions.select_default,
          ['<F2>.'] = actions.file_vsplit,
          ['<F2>,'] = actions.file_split,
          ['<F2>n'] = actions.file_tab,
          ['<C-q>'] = actions.send_selected_to_qflist + actions.open_qflist,
          ['<C-d>'] = actions.preview_scrolling_down,
          ['<C-u>'] = actions.preview_scrolling_up,
          ['<C-j>'] = actions.preview_scrolling_down,
          ['<C-k>'] = actions.preview_scrolling_up,
          -- ['<C-h>'] = actions.preview_scrolling_left,
          -- ['<C-l>'] = actions.preview_scrolling_right,
        },
        n = {
          ['u'] = { '<cmd>undo<cr>', type = 'command' }, -- didn't work by default
          ['<CR>'] = actions.select_default,
          ['<F2>.'] = actions.file_vsplit,
          ['<F2>,'] = actions.file_split,
          ['<F2>n'] = actions.file_tab,
          ['<Up>'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_previous, bufnr, 4)
          end,
          ['<Down>'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_next, bufnr, 4)
          end,
          ['K'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_previous, bufnr, 20)
          end,
          ['J'] = function(bufnr)
            helpers.repeat_function(actions.move_selection_next, bufnr, 20)
          end,
          ['<C-j>'] = actions.preview_scrolling_down,
          ['<C-k>'] = actions.preview_scrolling_up,
          -- ['<C-h>'] = actions.preview_scrolling_left,
          -- ['<C-l>'] = actions.preview_scrolling_right,
          ['<Tab>'] = function(bufnr)
            actions.toggle_selection(bufnr)
            actions.move_selection_next(bufnr)
          end,
          ['<S-Tab>'] = function(bufnr)
            actions.toggle_selection(bufnr)
            actions.move_selection_previous(bufnr)
          end,
          -- open find files picker for current path
          ['<BS><BS>'] = function(bufnr)
            local picker = action_state.get_current_picker(bufnr)
            local path = picker.finder.path
            if path then
              print(path)
              vim.cmd('Telescope find_files cwd=' .. path)
            end
          end,
          -- open live grep picker for current path
          ['<BS>/'] = function(bufnr)
            local picker = action_state.get_current_picker(bufnr)
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
    },
    extensions = {
      -- :h telescope-file-browser.picker
      file_browser = {
        initial_mode = 'normal',
        sorting_strategy = 'ascending',
        path = vim.loop.cwd(),
        cwd = vim.loop.cwd(),
        cwd_to_path = false,
        grouped = true,
        files = true,
        add_dirs = true,
        depth = 1,
        auto_depth = false,
        select_buffer = false,
        hidden = { file_browser = true, folder_browser = true },
        respect_gitignore = false,
        follow_symlinks = true,
        browse_files = require('telescope._extensions.file_browser.finders').browse_files,
        browse_folders = require('telescope._extensions.file_browser.finders').browse_folders,
        hide_parent_dir = true,
        collapse_dirs = false,
        prompt_path = false,
        quiet = false,
        dir_icon = ' ',
        dir_icon_hl = 'Default',
        display_stat = { date = true, size = true, mode = true },
        hijack_netrw = true,
        use_fd = true,
        git_status = true,
        mappings = {
          ['i'] = {
            -- disabling defaults
            ['<A-c>'] = false,
            ['<A-r>'] = false,
            ['<A-m>'] = false,
            ['<A-y>'] = false,
            ['<A-d>'] = false,
            ['<C-o>'] = false,
            ['<C-g>'] = false,
            ['<C-e>'] = false,
            ['<C-w>'] = false,
            ['<C-t>'] = false,
            ['<C-f>'] = false,
            ['<C-h>'] = false,
            ['<C-s>'] = false,
            ['<bs>'] = false,

            ['<S-CR>'] = fb_actions.create_from_prompt,
            ['<BS>'] = fb_actions.backspace,
            ['<CR>'] = function(bufnr)
              actions.select_default(bufnr)
              vim.api.nvim_feedkeys(
                vim.api.nvim_replace_termcodes('<Esc>', true, true, true),
                'n',
                false
              )
            end,
          },

          ['n'] = {
            -- disabling defaults
            ['c'] = false,
            ['r'] = false,
            -- ['m'] = false,
            ['y'] = false,
            ['d'] = false,
            ['o'] = false,
            ['g'] = false,
            ['e'] = false,
            ['w'] = false,
            ['t'] = false,
            ['f'] = false,
            -- ['h'] = false,
            ['s'] = false,
            -- ['<Esc>'] = false,

            ['%'] = fb_actions.create,
            ['R'] = fb_actions.rename,
            ['m'] = fb_actions.move,
            ['P'] = fb_actions.copy,
            -- delete to trash
            ['dD'] = function(bufnr)
              local picker_path =
                action_state.get_current_picker(bufnr).finder.path
              local selection_paths = {}
              action_utils.map_selections(bufnr, function(entry)
                table.insert(selection_paths, entry[1])
              end)
              if #selection_paths == 0 then
                -- delete highlighted entry
                local selected_path = action_state.get_selected_entry(bufnr)[1]
                vim.cmd('!trash ' .. selected_path)
              else
                -- delete selected entries
                for _, v in ipairs(selection_paths) do
                  vim.cmd('!trash ' .. v)
                end
              end
              vim.cmd('Telescope file_browser path=' .. picker_path)
            end,
            -- delete permanently
            ['dX'] = function(bufnr)
              fb_actions.remove(bufnr)
            end,
            -- 'undo' delete (open trash restore for current dir)
            ['ud'] = function(bufnr)
              local picker_path =
                action_state.get_current_picker(bufnr).finder.path
              actions.close(bufnr)
              Lpke_trash_restore(picker_path)
            end,
            ['O'] = fb_actions.open,
            ['gh'] = fb_actions.goto_home_dir,
            ['gd'] = fb_actions.goto_cwd,
            ['cd'] = fb_actions.change_cwd,
            [','] = fb_actions.toggle_browser,
            [';'] = fb_actions.toggle_hidden,
            ['g;'] = fb_actions.toggle_respect_gitignore,
            ['v'] = fb_actions.toggle_all,
            ['uv'] = actions.drop_all,
            ['h'] = fb_actions.goto_parent_dir,
            ['l'] = actions.select_default,
            ['/'] = { 'i', type = 'command' },
            -- ['<Esc><Esc>'] = { '<cmd>q!<CR>', type = 'command' },
          },
        },
      },
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
