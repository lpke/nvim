local function config()
  local diffview = require('diffview')
  local actions = require('diffview.actions')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- helpers
  local function diffview_close()
    vim.cmd('DiffviewClose')
    local current_tab = vim.fn.tabpagenr()
    if current_tab > 1 then
      vim.cmd('tabprevious')
    end
  end

  local function prev_conflict(key)
    actions.prev_conflict()
    Lpke_square_repeat_key = key
  end
  local function next_conflict(key)
    actions.next_conflict()
    Lpke_square_repeat_key = key
  end

  diffview.setup({
    diff_binaries = false, -- Show diffs for binaries
    enhanced_diff_hl = true, -- See |diffview-config-enhanced_diff_hl|
    git_cmd = { 'git' }, -- The git executable followed by default args.
    hg_cmd = { 'hg' }, -- The hg executable followed by default args.
    use_icons = true, -- Requires nvim-web-devicons
    show_help_hints = true, -- Show hints for how to open the help panel
    watch_index = true, -- Update views and index buffers when the git index changes.

    icons = { -- Only applies when use_icons is true.
      -- folder_closed = '',
      -- folder_open = '',
      folder_closed = ' ',
      folder_open = ' ',
    },
    signs = {
      fold_closed = '',
      fold_open = '',
      done = '✓',
    },

    view = {
      -- Configure the layout and behavior of different types of views.
      -- Available layouts:
      --  'diff1_plain'
      --    |'diff2_horizontal'
      --    |'diff2_vertical'
      --    |'diff3_horizontal'
      --    |'diff3_vertical'
      --    |'diff3_mixed'
      --    |'diff4_mixed'
      -- For more info, see |diffview-config-view.x.layout|.
      default = {
        -- Config for changed files, and staged files in diff views.
        layout = 'diff2_horizontal',
        disable_diagnostics = false, -- Temporarily disable diagnostics for diff buffers while in the view.
        winbar_info = false, -- See |diffview-config-view.x.winbar_info|
      },
      merge_tool = {
        -- Config for conflicted files in diff views during a merge or rebase.
        layout = 'diff4_mixed',
        disable_diagnostics = true, -- Temporarily disable diagnostics for diff buffers while in the view.
        winbar_info = true, -- See |diffview-config-view.x.winbar_info|
      },
      file_history = {
        -- Config for changed files in file history views.
        layout = 'diff2_horizontal',
        disable_diagnostics = false, -- Temporarily disable diagnostics for diff buffers while in the view.
        winbar_info = false, -- See |diffview-config-view.x.winbar_info|
      },
    },

    file_panel = {
      listing_style = 'tree', -- One of 'list' or 'tree'
      tree_options = { -- Only applies when listing_style is 'tree'
        flatten_dirs = true, -- Flatten dirs that only contain one single dir
        folder_statuses = 'only_folded', -- One of 'never', 'only_folded' or 'always'.
      },
      win_config = { -- See |diffview-config-win_config|
        position = 'left',
        width = 35,
        win_opts = {},
      },
    },

    file_history_panel = {
      log_options = { -- See |diffview-config-log_options|
        git = {
          single_file = {
            diff_merges = 'combined',
          },
          multi_file = {
            diff_merges = 'first-parent',
          },
        },
        hg = {
          single_file = {},
          multi_file = {},
        },
      },
      win_config = { -- See |diffview-config-win_config|
        position = 'bottom',
        height = 16,
        win_opts = {},
      },
    },

    commit_log_panel = {
      win_config = {}, -- See |diffview-config-win_config|
    },

    default_args = { -- Default args prepended to the arg-list for the listed commands
      DiffviewOpen = {},
      DiffviewFileHistory = {},
    },

    hooks = {}, -- See |diffview-config-hooks|

    -- stylua: ignore start
    keymaps = {
      disable_defaults = true, -- Disable the default keymaps

      view = {
        -- The `view` bindings are active in the diff buffers, only when the current
        -- tabpage is a Diffview.
        { 'n', '<tab>',       actions.select_next_entry,              { desc = 'Diffview: Open the diff for the next file' } },
        { 'n', 'J',           actions.select_next_entry,              { desc = 'Diffview: Open the diff for the next file' } },
        { 'n', '<s-tab>',     actions.select_prev_entry,              { desc = 'Diffview: Open the diff for the previous file' } },
        { 'n', 'K',           actions.select_prev_entry,              { desc = 'Diffview: Open the diff for the previous file' } },
        { 'n', '[F',          actions.select_first_entry,             { desc = 'Diffview: Open the diff for the first file' } },
        { 'n', ']F',          actions.select_last_entry,              { desc = 'Diffview: Open the diff for the last file' } },
        { 'n', 'gf',          actions.goto_file_edit,                 { desc = 'Diffview: Open the file in the previous tabpage' } },
        { 'n', '<C-w><C-f>',  actions.goto_file_split,                { desc = 'Diffview: Open the file in a new split' } },
        { 'n', '<C-w>gf',     actions.goto_file_tab,                  { desc = 'Diffview: Open the file in a new tabpage' } },
        { 'n', '<leader>e',   actions.focus_files,                    { desc = 'Diffview: Bring focus to the file panel' } },
        { 'n', '<leader>b',   actions.toggle_files,                   { desc = 'Diffview: Toggle the file panel.' } },
        { 'n', 'g<C-x>',      actions.cycle_layout,                   { desc = 'Diffview: Cycle through available layouts.' } },
        { 'n', '[x',          function() prev_conflict('x') end,      { desc = 'Diffview: In the merge-tool: jump to the previous conflict' } },
        { 'n', ']x',          function() next_conflict('x') end,      { desc = 'Diffview: In the merge-tool: jump to the next conflict' } },
        { 'n', '<leader>co',  actions.conflict_choose('ours'),        { desc = 'Diffview: Choose the OURS version of a conflict' } },
        { 'n', '<leader>ct',  actions.conflict_choose('theirs'),      { desc = 'Diffview: Choose the THEIRS version of a conflict' } },
        { 'n', '<leader>cb',  actions.conflict_choose('base'),        { desc = 'Diffview: Choose the BASE version of a conflict' } },
        { 'n', '<leader>ca',  actions.conflict_choose('all'),         { desc = 'Diffview: Choose all the versions of a conflict' } },
        { 'n', 'dx',          actions.conflict_choose('none'),        { desc = 'Diffview: Delete the conflict region' } },
        { 'n', '<leader>cO',  actions.conflict_choose_all('ours'),    { desc = 'Diffview: Choose the OURS version of a conflict for the whole file' } },
        { 'n', '<leader>cT',  actions.conflict_choose_all('theirs'),  { desc = 'Diffview: Choose the THEIRS version of a conflict for the whole file' } },
        { 'n', '<leader>cB',  actions.conflict_choose_all('base'),    { desc = 'Diffview: Choose the BASE version of a conflict for the whole file' } },
        { 'n', '<leader>cA',  actions.conflict_choose_all('all'),     { desc = 'Diffview: Choose all the versions of a conflict for the whole file' } },
        { 'n', 'dX',          actions.conflict_choose_all('none'),    { desc = 'Diffview: Delete the conflict region for the whole file' } },
        { 'n', '<A-/>',       diffview_close,                         { desc = 'Diffview: Close the Diffview tab' } },
        { 'n', '<F2>/',       diffview_close,                         { desc = 'Diffview: Close the Diffview tab' } },
      },

      diff1 = {
        -- Mappings in single window diff layouts
        { 'n', 'g?', actions.help({ 'view', 'diff1' }), { desc = 'Diffview: Open the help panel' } },
      },

      diff2 = {
        -- Mappings in 2-way diff layouts
        { 'n', 'g?', actions.help({ 'view', 'diff2' }), { desc = 'Diffview: Open the help panel' } },
      },

      diff3 = {
        -- Mappings in 3-way diff layouts
        { { 'n', 'x' }, '2do',  actions.diffget('ours'),            { desc = 'Diffview: Obtain the diff hunk from the OURS version of the file' } },
        { { 'n', 'x' }, '3do',  actions.diffget('theirs'),          { desc = 'Diffview: Obtain the diff hunk from the THEIRS version of the file' } },
        { 'n',          'g?',   actions.help({ 'view', 'diff3' }),  { desc = 'Diffview: Open the help panel' } },
      },

      diff4 = {
        -- Mappings in 4-way diff layouts
        { { 'n', 'x' }, '1do',  actions.diffget('base'),            { desc = 'Diffview: Obtain the diff hunk from the BASE version of the file' } },
        { { 'n', 'x' }, '2do',  actions.diffget('ours'),            { desc = 'Diffview: Obtain the diff hunk from the OURS version of the file' } },
        { { 'n', 'x' }, '3do',  actions.diffget('theirs'),          { desc = 'Diffview: Obtain the diff hunk from the THEIRS version of the file' } },
        { 'n',          'g?',   actions.help({ 'view', 'diff4' }),  { desc = 'Diffview: Open the help panel' } },
      },

      file_panel = {
        { 'n', 'j',              actions.next_entry,                     { desc = 'Diffview: Bring the cursor to the next file entry' } },
        { 'n', '<down>',         actions.next_entry,                     { desc = 'Diffview: Bring the cursor to the next file entry' } },
        { 'n', 'k',              actions.prev_entry,                     { desc = 'Diffview: Bring the cursor to the previous file entry' } },
        { 'n', '<up>',           actions.prev_entry,                     { desc = 'Diffview: Bring the cursor to the previous file entry' } },
        { 'n', '<cr>',           actions.select_entry,                   { desc = 'Diffview: Open the diff for the selected entry' } },
        { 'n', '=',              actions.toggle_fold,                    { desc = 'Diffview: Open the diff for the selected entry' } },
        { 'n', 'o',              actions.select_entry,                   { desc = 'Diffview: Open the diff for the selected entry' } },
        { 'n', 'l',              actions.select_entry,                   { desc = 'Diffview: Open the diff for the selected entry' } },
        { 'n', '<2-LeftMouse>',  actions.select_entry,                   { desc = 'Diffview: Open the diff for the selected entry' } },
        { 'n', '-',              actions.toggle_stage_entry,             { desc = 'Diffview: Stage / unstage the selected entry' } },
        { 'n', 's',              actions.toggle_stage_entry,             { desc = 'Diffview: Stage / unstage the selected entry' } },
        { 'n', 'S',              actions.stage_all,                      { desc = 'Diffview: Stage all entries' } },
        { 'n', 'U',              actions.unstage_all,                    { desc = 'Diffview: Unstage all entries' } },
        { 'n', 'X',              actions.restore_entry,                  { desc = 'Diffview: Restore entry to the state on the left side' } },
        { 'n', 'L',              actions.open_commit_log,                { desc = 'Diffview: Open the commit log panel' } },
        { 'n', 'za',             actions.open_fold,                      { desc = 'Diffview: Expand fold' } },
        { 'n', 'h',              actions.close_fold,                     { desc = 'Diffview: Collapse fold' } },
        { 'n', 'zc',             actions.close_fold,                     { desc = 'Diffview: Collapse fold' } },
        { 'n', 'zo',             actions.toggle_fold,                    { desc = 'Diffview: Toggle fold' } },
        { 'n', 'zR',             actions.open_all_folds,                 { desc = 'Diffview: Expand all folds' } },
        { 'n', 'zM',             actions.close_all_folds,                { desc = 'Diffview: Collapse all folds' } },
        { 'n', '<c-b>',          actions.scroll_view(-0.25),             { desc = 'Diffview: Scroll the view up' } },
        { 'n', '<c-f>',          actions.scroll_view(0.25),              { desc = 'Diffview: Scroll the view down' } },
        { 'n', '<tab>',          actions.select_next_entry,              { desc = 'Diffview: Open the diff for the next file' } },
        { 'n', 'J',              actions.select_next_entry,              { desc = 'Diffview: Open the diff for the next file' } },
        { 'n', '<s-tab>',        actions.select_prev_entry,              { desc = 'Diffview: Open the diff for the previous file' } },
        { 'n', 'K',              actions.select_prev_entry,              { desc = 'Diffview: Open the diff for the previous file' } },
        { 'n', '[F',             actions.select_first_entry,             { desc = 'Diffview: Open the diff for the first file' } },
        { 'n', ']F',             actions.select_last_entry,              { desc = 'Diffview: Open the diff for the last file' } },
        { 'n', 'gf',             actions.goto_file_edit,                 { desc = 'Diffview: Open the file in the previous tabpage' } },
        { 'n', '<C-w><C-f>',     actions.goto_file_split,                { desc = 'Diffview: Open the file in a new split' } },
        { 'n', '<C-w>gf',        actions.goto_file_tab,                  { desc = 'Diffview: Open the file in a new tabpage' } },
        { 'n', 'i',              actions.listing_style,                  { desc = "Diffview: Toggle between 'list' and 'tree' views" } },
        { 'n', 'f',              actions.toggle_flatten_dirs,            { desc = 'Diffview: Flatten empty subdirectories in tree listing style' } },
        { 'n', 'R',              actions.refresh_files,                  { desc = 'Diffview: Update stats and entries in the file list' } },
        { 'n', '<leader>e',      actions.focus_files,                    { desc = 'Diffview: Bring focus to the file panel' } },
        { 'n', '<leader>b',      actions.toggle_files,                   { desc = 'Diffview: Toggle the file panel' } },
        { 'n', 'g<C-x>',         actions.cycle_layout,                   { desc = 'Diffview: Cycle available layouts' } },
        { 'n', '[x',             function() prev_conflict('x') end,      { desc = 'Diffview: Go to the previous conflict' } },
        { 'n', ']x',             function() next_conflict('x') end,      { desc = 'Diffview: Go to the next conflict' } },
        { 'n', 'g?',             actions.help('file_panel'),             { desc = 'Diffview: Open the help panel' } },
        { 'n', '<leader>cO',     actions.conflict_choose_all('ours'),    { desc = 'Diffview: Choose the OURS version of a conflict for the whole file' } },
        { 'n', '<leader>cT',     actions.conflict_choose_all('theirs'),  { desc = 'Diffview: Choose the THEIRS version of a conflict for the whole file' } },
        { 'n', '<leader>cB',     actions.conflict_choose_all('base'),    { desc = 'Diffview: Choose the BASE version of a conflict for the whole file' } },
        { 'n', '<leader>cA',     actions.conflict_choose_all('all'),     { desc = 'Diffview: Choose all the versions of a conflict for the whole file' } },
        { 'n', 'dX',             actions.conflict_choose_all('none'),    { desc = 'Diffview: Delete the conflict region for the whole file' } },
        { 'n', '<A-/>',          diffview_close,                         { desc = 'Diffview: Close the Diffview tab' } },
        { 'n', '<F2>/',          diffview_close,                         { desc = 'Diffview: Close the Diffview tab' } },
      },

      file_history_panel = {
        { 'n', 'g!',            actions.options,                     { desc = 'Diffview: Open the option panel' } },
        { 'n', '<C-A-d>',       actions.open_in_diffview,            { desc = 'Diffview: Open the entry under the cursor in a diffview' } },
        { 'n', 'y',             actions.copy_hash,                   { desc = 'Diffview: Copy the commit hash of the entry under the cursor' } },
        { 'n', 'L',             actions.open_commit_log,             { desc = 'Diffview: Show commit details' } },
        { 'n', 'X',             actions.restore_entry,               { desc = 'Diffview: Restore file to the state from the selected entry' } },
        { 'n', 'za',            actions.open_fold,                   { desc = 'Diffview: Expand fold' } },
        { 'n', 'zc',            actions.close_fold,                  { desc = 'Diffview: Collapse fold' } },
        { 'n', 'h',             actions.close_fold,                  { desc = 'Diffview: Collapse fold' } },
        { 'n', 'zo',            actions.toggle_fold,                 { desc = 'Diffview: Toggle fold' } },
        { 'n', 'zR',            actions.open_all_folds,              { desc = 'Diffview: Expand all folds' } },
        { 'n', 'zM',            actions.close_all_folds,             { desc = 'Diffview: Collapse all folds' } },
        { 'n', 'j',             actions.next_entry,                  { desc = 'Diffview: Bring the cursor to the next file entry' } },
        { 'n', 'k',             actions.prev_entry,                  { desc = 'Diffview: Bring the cursor to the previous file entry' } },
        { 'n', '<cr>',          actions.select_entry,                { desc = 'Diffview: Open the diff for the selected entry' } },
        { 'n', '=',             actions.toggle_fold,                 { desc = 'Diffview: Open the diff for the selected entry' } },
        { 'n', 'o',             actions.select_entry,                { desc = 'Diffview: Open the diff for the selected entry' } },
        { 'n', 'l',             actions.select_entry,                { desc = 'Diffview: Open the diff for the selected entry' } },
        { 'n', '<2-LeftMouse>', actions.select_entry,                { desc = 'Diffview: Open the diff for the selected entry' } },
        { 'n', '<c-b>',         actions.scroll_view(-0.25),          { desc = 'Diffview: Scroll the view up' } },
        { 'n', '<c-f>',         actions.scroll_view(0.25),           { desc = 'Diffview: Scroll the view down' } },
        { 'n', '<tab>',         actions.select_next_entry,           { desc = 'Diffview: Open the diff for the next file' } },
        { 'n', 'J',             actions.select_next_entry,           { desc = 'Diffview: Open the diff for the next file' } },
        { 'n', '<s-tab>',       actions.select_prev_entry,           { desc = 'Diffview: Open the diff for the previous file' } },
        { 'n', 'K',             actions.select_prev_entry,           { desc = 'Diffview: Open the diff for the previous file' } },
        { 'n', '[F',            actions.select_first_entry,          { desc = 'Diffview: Open the diff for the first file' } },
        { 'n', ']F',            actions.select_last_entry,           { desc = 'Diffview: Open the diff for the last file' } },
        { 'n', 'gf',            actions.goto_file_edit,              { desc = 'Diffview: Open the file in the previous tabpage' } },
        { 'n', '<C-w><C-f>',    actions.goto_file_split,             { desc = 'Diffview: Open the file in a new split' } },
        { 'n', '<C-w>gf',       actions.goto_file_tab,               { desc = 'Diffview: Open the file in a new tabpage' } },
        { 'n', '<leader>e',     actions.focus_files,                 { desc = 'Diffview: Bring focus to the file panel' } },
        { 'n', '<leader>b',     actions.toggle_files,                { desc = 'Diffview: Toggle the file panel' } },
        { 'n', 'g<C-x>',        actions.cycle_layout,                { desc = 'Diffview: Cycle available layouts' } },
        { 'n', 'g?',            actions.help('file_history_panel'),  { desc = 'Diffview: Open the help panel' } },
        { 'n', '<A-/>',         diffview_close,                      { desc = 'Diffview: Close the Diffview tab' } },
        { 'n', '<F2>/',         diffview_close,                      { desc = 'Diffview: Close the Diffview tab' } },
      },

      option_panel = {
        { 'n', '<tab>', actions.select_entry,          { desc = 'Diffview: Change the current option' } },
        { 'n', 'q',     actions.close,                 { desc = 'Diffview: Close the panel' } },
        { 'n', 'g?',    actions.help('option_panel'),  { desc = 'Diffview: Open the help panel' } },
      },

      help_panel = {
        { 'n', 'q',     actions.close,  { desc = 'Diffview: Close help menu' } },
        { 'n', '<esc>', actions.close,  { desc = 'Diffview: Close help menu' } },
      },
    },
    -- stylua: ignore end
  })

  -- stylua: ignore start
  helpers.keymap_set_multi({
    { 'nC', '<leader>gc', 'DiffviewFileHistory %', { desc = 'Diffview: Open file commit history' } },
    { 'nC', '<BS>gc', 'DiffviewFileHistory', { desc = 'Diffview: Open current branch commit history' } },
    { 'nC', '<BS>gs', 'DiffviewFileHistory -g --range=stash', { desc = 'Diffview: Open stashes in a file history view' } },
    { 'nC', '<BS>gd', 'DiffviewOpen', { desc = 'Diffview: Open diff view for current changed/staged' } },
    { 'nC', '<leader>I', 'DiffviewOpen', { desc = 'Diffview: Open diff view for current changed/staged' } },
    { 'n', '<BS>gH', function()
      vim.cmd('call feedkeys(":DiffviewFileHistory ")')
    end, { desc = 'Diffview: Prepare to open a file history view (provide paths)' } },
    { 'n', '<BS>gD', function()
      vim.cmd('call feedkeys(":DiffviewOpen ")')
    end, { desc = 'Diffview: Prepare to open a diff view (provide revs)' } },
  })

  helpers.set_hl_multi({
    ['DiffViewStatusUnmerged'] = { bg = 'none', fg = tc.love, bold = true },
    ['DiffViewStatusUntracked'] = { bg = 'none', fg = tc.pine },
    ['DiffViewStatusModified'] = { bg = 'none', fg = tc.rose },
    ['DiffViewStatusAdded'] = { bg = 'none', fg = tc.foam },
    ['DiffViewStatusRenamed'] = { bg = 'none', fg = tc.iris },
    ['DiffViewStatusDeleted'] = { bg = 'none', fg = tc.love },
    ['DiffViewStatusBroken'] = { bg = 'none', fg = tc.love },
    ['DiffViewStatusUnknown'] = { bg = 'none', fg = tc.love },
    ['DiffViewFilePanelSelected'] = { bg = 'none', fg = tc.iris, bold = true },
    ['DiffViewFilePanelInsertions'] = { bg = 'none', fg = tc.foam },
    ['DiffViewFilePanelDeletions'] = { bg = 'none', fg = tc.love },
    ['DiffViewFilePanelCounter'] = { bg = 'none', fg = tc.text, bold = false },
    ['DiffViewHash'] = { bg = 'none', fg = tc.subtle },
    ['DiffViewFilePanelFileName'] = { bg = 'none', fg = tc.text },
    ['DiffViewFilePanelPath'] = { bg = 'none', fg = tc.subtle, italic = false },
  })
  -- stylua: ignore end
end

return {
  'sindrets/diffview.nvim',
  event = 'VeryLazy',
  config = config,
}
