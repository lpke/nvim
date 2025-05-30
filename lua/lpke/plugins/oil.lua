local function config()
  local oil = require('oil')
  local helpers = require('lpke.core.helpers')

  local function cd(cmd)
    local cur_dir = oil.get_current_dir()
    if cur_dir then
      vim.cmd(cmd .. ' ' .. cur_dir)
      pcall(function()
        require('lualine').refresh()
      end)
    end
  end

  -- stylua: ignore start
  helpers.keymap_set_multi({
    -- open in current window
    {'nC', '<BS>s', 'Oil', { desc = 'Open Oil File Browser' }},
    {'nC', '-', 'Oil', { desc = 'Open Oil File Browser' }},
    -- open in a new split (neovim-wide)
    {'nC', '<F2>>', 'vsplit | Oil', { desc = 'Open Oil File Browser at current location (v split)' }},
    {'nC', '<A->>', 'vsplit | Oil', { desc = 'Open Oil File Browser at current location (v split)' }}, -- FIXME
    {'nC', '<F2><', 'split | Oil', { desc = 'Open Oil File Browser at current location (h split)' }},
    {'nC', '<A-<>>', 'split | Oil', { desc = 'Open Oil File Browser at current location (h split)' }}, -- FIXME
  })
  -- stylua: ignore end

  oil.setup({
    -- Oil will take over directory buffers (e.g. `vim .` or `:e src/`)
    -- Set to false if you still want to use netrw.
    default_file_explorer = true,
    -- Id is automatically added at the beginning, and name at the end
    -- See :help oil-columns
    columns = {
      -- 'icon',
      -- 'permissions',
      -- 'size',
      -- 'mtime',
    },
    -- Buffer-local options to use for oil buffers
    buf_options = {
      buflisted = false,
      bufhidden = 'hide',
    },
    -- Window-local options to use for oil buffers
    win_options = {
      wrap = false,
      signcolumn = 'no',
      cursorcolumn = false,
      foldcolumn = '0',
      spell = false,
      list = false,
      conceallevel = 3,
      concealcursor = 'nvic',
    },
    -- Send deleted files to the trash instead of permanently deleting them (:help oil-trash)
    delete_to_trash = true,
    -- Skip the confirmation popup for simple operations
    skip_confirm_for_simple_edits = true,
    -- Selecting a new/moved/renamed file or directory will prompt you to save changes first
    prompt_save_on_select_new_entry = true,
    -- Oil will automatically delete hidden buffers after this delay
    -- You can set the delay to false to disable cleanup entirely
    -- Note that the cleanup process only starts when none of the oil buffers are currently displayed
    cleanup_delay_ms = 2000,
    -- Keymaps in oil buffer. Can be any value that `vim.keymap.set` accepts OR a table of keymap
    -- options with a `callback` (e.g. { callback = function() ... end, desc = "", mode = "n" })
    -- Additionally, if it is a string that matches "actions.<name>",
    -- it will use the mapping at require("oil.actions").<name>
    -- Set to `false` to remove a keymap
    -- See :help oil-actions for a list of all available actions
    use_default_keymaps = false,
    keymaps = {
      ['g?'] = 'actions.show_help',
      ['<C-c>'] = 'actions.close',
      ['<C-l>'] = 'actions.refresh',
      -- navigation
      ['<CR>'] = {
        callback = function()
          local entry = oil.get_cursor_entry()
          if not entry then
            return
          end
          local dir = oil.get_current_dir()
          local fullpath = dir .. entry.name
          if vim.env.IN_VSCODE and vim.fn.isdirectory(fullpath) == 0 then
            vim.fn.jobstart({ 'cursor', '-r', fullpath })
          else
            oil.select()
          end
        end,
        desc = 'If IN_VSCODE and file, run "cursor -r", else open normally',
        mode = 'n',
      },
      ['<leader><CR>'] = {
        callback = function()
          local dir = oil.get_current_dir()
          local entry = oil.get_cursor_entry()
          if entry then
            local fullpath = dir .. entry.name
            vim.fn.jobstart({ 'cursor', '-r', fullpath })
          end
        end,
        desc = 'Run "cursor -r" on selected entry',
        mode = 'n',
      },
      ['-'] = 'actions.parent',
      ['gd'] = 'actions.open_cwd',
      ['gh'] = {
        callback = function()
          oil.open('~/')
        end,
        desc = 'Open oil in the home (~/) folder',
        mode = 'n',
      },
      -- cd
      ['cdg'] = {
        callback = function()
          local dir = oil.get_current_dir()
          local git_root = vim.fn.system('cd ' .. vim.fn.shellescape(dir) .. ' && git rev-parse --show-toplevel'):gsub('\n', '')
          if vim.v.shell_error == 0 and git_root ~= '' then
            vim.cmd('cd ' .. vim.fn.fnameescape(git_root))
          else
            vim.notify('Not a git repository', vim.log.levels.WARN)
          end
        end,
        desc = ':cd to the git root of the current directory',
        mode = 'n',
      },
      ['cdc'] = {
        callback = function()
          cd('cd')
        end,
        desc = ':cd to the current oil directory (changes whole session)',
        mode = 'n',
      },
      ['cdt'] = {
        callback = function()
          cd('tcd')
        end,
        desc = ':tcd to the current oil directory (tab scoped)',
        mode = 'n',
      },
      ['cdl'] = {
        callback = function()
          cd('lcd')
        end,
        desc = ':lcd to the current oil directory (window scoped)',
        mode = 'n',
      },
      -- view/toggles
      ['<F2>p'] = 'actions.preview',
      ['<A-p>'] = 'actions.preview',
      ['gs'] = 'actions.change_sort',
      ['g.'] = 'actions.toggle_hidden',
      ['g\\'] = 'actions.toggle_trash',
      -- new window
      ['<F2>.'] = 'actions.select_vsplit',
      ['<A-.>'] = 'actions.select_vsplit',
      ['<F2>,'] = 'actions.select_split',
      ['<A-,>'] = 'actions.select_split',
      ['<F2>n'] = 'actions.select_tab',
      ['<A-n>'] = 'actions.select_tab',
      -- override default bind for this to keep oil at same dir when splitting from within oil
      ['<F2>>'] = {
        desc = 'Open Oil File Browser (v split)',
        callback = function()
          vim.cmd('vsplit')
        end,
        mode = 'n',
      },
      ['<A->>'] = { -- FIXME
        desc = 'Open Oil File Browser (v split)',
        callback = function()
          vim.cmd('vsplit')
        end,
        mode = 'n',
      },
      ['<F2><'] = {
        callback = function()
          vim.cmd('split')
        end,
        desc = 'Open Oil File Browser (h split)',
        mode = 'n',
      },
      ['<A-<>'] = { -- FIXME
        callback = function()
          vim.cmd('split')
        end,
        desc = 'Open Oil File Browser (h split)',
        mode = 'n',
      },
      -- yanking
      ['yd'] = {
        callback = function()
          local dir = oil.get_current_dir()
          Lpke_yank(dir, '"*+')
        end,
        desc = 'Yank the path of the current directory',
        mode = 'n',
      },
      ['yp'] = {
        callback = function()
          local dir = oil.get_current_dir()
          local name = oil.get_cursor_entry().name
          local path = dir .. name
          Lpke_yank(path, '"*+')
        end,
        desc = 'Yank the path of the currently selected item',
        mode = 'n',
      },
      -- disabled defaults
      -- ['gx'] = 'actions.open_external',
    },
    view_options = {
      -- Show files and directories that start with "."
      show_hidden = true,
      -- This function defines what is considered a "hidden" file
      is_hidden_file = function(name) -- (name, bufnr)
        return vim.startswith(name, '.')
      end,
      -- This function defines what will never be shown, even when `show_hidden` is set
      is_always_hidden = function(name) -- (name, bufnr)
        return name == '..'
      end,
      sort = {
        -- sort order can be "asc" or "desc"
        -- see :help oil-columns to see which columns are sortable
        { 'type', 'asc' },
        { 'name', 'asc' },
      },
    },
    -- Configuration for the floating window in oil.open_float
    float = {
      -- Padding around the floating window
      padding = 2,
      max_width = 0,
      max_height = 0,
      border = 'rounded',
      win_options = {
        winblend = 0,
      },
      -- This is the config that will be passed to nvim_open_win.
      -- Change values here to customize the layout
      override = function(conf)
        return conf
      end,
    },
    -- Configuration for the actions floating preview window
    preview = {
      -- Width dimensions can be integers or a float between 0 and 1 (e.g. 0.4 for 40%)
      -- min_width and max_width can be a single value or a list of mixed integer/float types.
      -- max_width = {100, 0.8} means "the lesser of 100 columns or 80% of total"
      max_width = 0.9,
      -- min_width = {40, 0.4} means "the greater of 40 columns or 40% of total"
      min_width = { 40, 0.4 },
      -- optionally define an integer/float for the exact width of the preview window
      width = nil,
      -- Height dimensions can be integers or a float between 0 and 1 (e.g. 0.4 for 40%)
      -- min_height and max_height can be a single value or a list of mixed integer/float types.
      -- max_height = {80, 0.9} means "the lesser of 80 columns or 90% of total"
      max_height = 0.9,
      -- min_height = {5, 0.1} means "the greater of 5 columns or 10% of total"
      min_height = { 5, 0.1 },
      -- optionally define an integer/float for the exact height of the preview window
      height = nil,
      border = 'rounded',
      win_options = {
        winblend = 0,
      },
    },
    -- Configuration for the floating progress window
    progress = {
      max_width = 0.9,
      min_width = { 40, 0.4 },
      width = nil,
      max_height = { 10, 0.9 },
      min_height = { 5, 0.1 },
      height = nil,
      border = 'rounded',
      minimized_border = 'none',
      win_options = {
        winblend = 0,
      },
    },
  })
end

return {
  'stevearc/oil.nvim',
  config = config,
}
