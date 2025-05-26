local helpers = require('lpke.core.helpers')
local options = require('lpke.core.options')
local keymap_set = helpers.keymap_set

--[[  SYNTAX: {'<modes><R=rec,E=expr,C=:,!=sil,D=delete>', <lhs>, <rhs>, <desc>, {opts}}

      NOTE:   I have '<M-[key]>' mapped to '<F2>[key]' in alacritty.
              This is because terminals treat <Alt> and <Esc> as the same key, and I
              don't want accidental <Esc> triggers when using my keybinds. ]]

vim.g.mapleader = ' '
-- stylua: ignore start
helpers.keymap_set_multi({
  -- removals
  {'n', ' ', ''}, -- no space after <leader>
  {'n', '<BS>', ''}, -- no BS after <BS>
  {'n', 'Q', ''}, -- use @@ instead
  {'ic', '<F2><CR>', ''}, -- used for cmp completion
  {'ic', '<A-CR>', ''}, -- used for cmp completion

  -- MacOS cmd -> ctrl parity
  {'n', '<D-o>', '<C-o>'},
  {'n', '<D-i>', '<C-i>'},

  -- High-level maps
  {'i', '<S-Tab>', '<Esc><<I', { desc = 'Unindent' }},
  {'nvi', '<C-s>', function() vim.cmd('w'); pcall(function() require('lualine').refresh() end) end, { desc = 'Save buffer' }},
  {'nvi', '<D-s>', function() vim.cmd('w'); pcall(function() require('lualine').refresh() end) end, { desc = 'Save buffer' }},
  {'c', '<Esc>', '<C-c>', { desc = 'Exit cmd-line with ctrl+c' }},
  {'i', '<C-c>', '<Esc>', { desc = 'Exit insert mode with ctrl+c, but still trigger `InsertLeave` autocmds' }},

  -- Tweaks/extensions of native functionality
  {'nv', '<leader>y', '"*y', { desc = 'Global yank' }},
  {'nv', '<leader>d', '"_d', { desc = 'Delete without copy' }},
  {'nv', 'gg', 'gg0', { desc = 'Go to very start of buffer' }},
  {'nv', 'G', 'G$', { desc = 'Go to very end of buffer' }},
  {'n', 'Y', 'y$', { desc = 'Yank to end of line' }},
  {'n', '<leader>Y', '"*y$', { desc = 'Global Yank to end of line' }},
  {'n', 'J', 'mzJ`z', { desc = 'Join lines (without moving cursor)' }},
  {'n', 'gJ', 'mzgJ`z', { desc = 'Join lines without modification (without moving cursor)' }},
  {'n', '<leader>J', 'mzgJi<Space><Esc>diW`z', { desc = 'Join lines without any spaces (without moving cursor)' }},
  {'n', 'go', 'o<Esc>', { desc = 'New line below (remain in normal mode)' }},
  {'n', 'gO', 'O<Esc>', { desc = 'New line above (remain in normal mode)' }},
  {'nv', '=*', 'mzgg=G`z', { desc = 'Indent entire file' }},
  {'nv', '=_', '==', { desc = 'Indent current line or selection only' }},
  {'nv', '<C-k>', '8k', { desc = 'Move up 8 lines' }},
  {'nv', '<D-k>', '8k', { desc = 'Move up 8 lines' }},
  {'nv', '<C-j>', '8j', { desc = 'Move down 8 lines' }},
  {'nv', '<D-j>', '8j', { desc = 'Move down 8 lines' }},
  {'nv', 'ze', 'zt8<C-y>', { desc = 'Centre cursor 8 lines below zt' }},
  {'nC', '<BS>L', 'botright copen', { desc = 'Open quick fix list' }},
  {'nC', '<leader>q', "call setqflist([{'filename': expand('%'), 'lnum': line('.'), 'col': col('.'), 'text': getline('.')}], 'a')",
    { desc = 'Add current file/position to quick fix list' }},

  -- glorified macros
  {'v', '<leader>ev', [[mx"zy<cmd>execute 's/\V' . getreg('z') . '/' . eval(@z) . '/'<CR>`x]],
    { desc = 'Replace selected text with the eval() version of itself' }},
  {'n', '<leader>%', [[mmyiwj^lvat<Esc>o</<Esc>pA><Esc>kV'mj><Esc>`m]],
    { desc = 'Wrap html element below with matching tag under cursor' }},
  {'v', '<leader>%', [[mmyj^lvat<Esc>o</<Esc>pA><Esc>kV'mj><Esc>`m]],
    { desc = 'Wrap html element below with matching tag of selected text' }},

  -- terminal
  {'nC', '<BS>t', 'Term', { desc = 'Open a floating terminal window' }},
  {'nC', '<BS>T', 'Term full', { desc = 'Open a floating terminal window (fullscreen)' }},
  {'nC', '<BS>r', 'Ranger', { desc = 'Open a floating ranger window' }},
  {'nC', '<BS>R', 'Ranger full', { desc = 'Open a floating ranger window (fullscreen)' }},
  {'t', '<F2>;', '<C-\\><C-n>', { desc = 'Enter vim normal mode from terminal' }},
  {'t', '<A-;>', '<C-\\><C-n>', { desc = 'Enter vim normal mode from terminal' }},
  {'t', '<F2>:', '<C-\\><C-n>:', { desc = 'Enter vim cmd-line from terminal' }},
  {'t', '<A-:>', '<C-\\><C-n>:', { desc = 'Enter vim cmd-line from terminal' }},
  {'t', '<F2>/', helpers.stop_term, { desc = 'Kill and close active terminal' }},
  {'t', '<A-/>', helpers.stop_term, { desc = 'Kill and close active terminal' }},

  -- Toggle UI/features
  {'nvC!', '<F2>w', 'set wrap!', { desc = 'Toggle line wrap' }},
  {'nvC!', '<A-w>', 'set wrap!', { desc = 'Toggle line wrap' }},
  {'nvC', '<F2>r', 'set relativenumber!', { desc = 'Toggle relative numbers' }},
  {'nvC', '<A-r>', 'set relativenumber!', { desc = 'Toggle relative numbers' }},
  -- FIXME: disabled due to lualine bug requiring me to set `globalstatue = true`
  -- {'n', '<F2>e', function() helpers.toggle_global_status() end,
  --   { desc = 'Toggle global status line' }},
  {'n!', '<F2>W', function() helpers.toggle_whitespace_hl(options.custom_opts.whitespace_hl) end,
    { desc = 'Toggle visible whitespace' }},
  {'n!', '<A-W>', function() helpers.toggle_whitespace_hl(options.custom_opts.whitespace_hl) end,
    { desc = 'Toggle visible whitespace' }},

  -- Fold management
  {'nv', 'zo', 'za', { desc = 'Toggle fold under cursor' }},
  {'nv', 'zO', 'zA', { desc = 'Toggle all nested folds under cursor' }},

  -- buffer navigation
  {'nviC', '<F2><Down>', 'bnext', { desc = 'Next buffer' }},
  {'nviC', '<A-Down>', 'bnext', { desc = 'Next buffer' }},
  {'nviC', '<F2><Up>', 'bprev', { desc = 'Previous buffer' }},
  {'nviC', '<A-Up>', 'bprev', { desc = 'Previous buffer' }},
  {'nvC', '<F2><BS>', 'bdelete', { desc = 'Delete buffer' }},
  {'nvC', '<A-BS>', 'bdelete', { desc = 'Delete buffer' }},

  -- window control
  -- creation / deletion
  {'nvC', '<C-w>.', 'vsplit', { desc = 'Split window horizontally' }},
  {'nvC', '<C-w>,', 'split', { desc = 'Split window vertically' }},
  {'nvC', '<F2>.', 'vsplit', { desc = 'Split window horizontally' }},
  {'nvC', '<F2>,', 'split', { desc = 'Split window vertically' }},
  {'nvC', '<A-.>', 'vsplit', { desc = 'Split window horizontally' }},
  {'nvC', '<A-,>', 'split', { desc = 'Split window vertically' }},
  {'n', '<C-w>x', Lpke_close_win, { desc = 'Close window (yank info)' }},
  {'n', '<F2>/', Lpke_close_win, { desc = 'Close window (yank info)' }},
  {'nC', 'QQ', 'qa', { desc = 'Quit all (:qa)' }},
  {'nC', 'QZ', 'wqa', { desc = 'Write and quit all (:wqa)' }},
  {'nC', '<C-w>QQ', 'lua require("auto-session").DisableAutoSave() ; vim.cmd("qa")', { desc = 'Quit all without auto-saving session (:qa)' }},
  {'nC', '<C-w>QZ', 'lua require("auto-session").DisableAutoSave() ; vim.cmd("wqa")', { desc = 'Write and quit all without auto-saving session (:wqa)' }},
  -- copy/pasting/rotating buffers
  {'nC', '<F2>y', 'lua Lpke_copy_buffer()', { desc = 'Yank current buffer details' }},
  {'nC', '<A-y>', 'lua Lpke_copy_buffer()', { desc = 'Yank current buffer details' }},
  {'nC', '<F2>p', 'lua Lpke_paste_buffer()', { desc = 'Paste yanked buffer details' }},
  {'nC', '<A-p>', 'lua Lpke_paste_buffer()', { desc = 'Paste yanked buffer details' }},
  {'n', '<F2>O', '<C-w>r', { desc = 'Rotate windows in current split' }},
  {'n', '<A-O>', '<C-w>r', { desc = 'Rotate windows in current split' }},
  -- copy/pasting layout
  {'nC', '<F2>Y', 'lua Lpke_copy_layout()', { desc = 'Yank current tab layout' }},
  {'nC', '<A-Y>', 'lua Lpke_copy_layout()', { desc = 'Yank current tab layout' }},
  {'nC', '<F2>P', 'lua Lpke_paste_layout()', { desc = 'Paste current tab layout' }},
  {'nC', '<A-P>', 'lua Lpke_paste_layout()', { desc = 'Paste current tab layout' }},
  -- navigation
  {'nv', '<F2>h', '<C-w>h', { desc = 'Focus window left' }},
  {'nv', '<F2>j', '<C-w>j', { desc = 'Focus window down' }},
  {'nv', '<F2>k', '<C-w>k', { desc = 'Focus window up' }},
  {'nv', '<F2>l', '<C-w>l', { desc = 'Focus window right' }},
  {'nv', '<A-h>', '<C-w>h', { desc = 'Focus window left' }},
  {'nv', '<A-j>', '<C-w>j', { desc = 'Focus window down' }},
  {'nv', '<A-k>', '<C-w>k', { desc = 'Focus window up' }},
  {'nv', '<A-l>', '<C-w>l', { desc = 'Focus window right' }},

  {'i', '<F2>h', '<Esc><C-w>h', { desc = 'Focus window left' }},
  {'i', '<F2>j', '<Esc><C-w>j', { desc = 'Focus window down' }},
  {'i', '<F2>k', '<Esc><C-w>k', { desc = 'Focus window up' }},
  {'i', '<F2>l', '<Esc><C-w>l', { desc = 'Focus window right' }},
  {'i', '<A-h>', '<Esc><C-w>h', { desc = 'Focus window left' }},
  {'i', '<A-j>', '<Esc><C-w>j', { desc = 'Focus window down' }},
  {'i', '<A-k>', '<Esc><C-w>k', { desc = 'Focus window up' }},
  {'i', '<A-l>', '<Esc><C-w>l', { desc = 'Focus window right' }},
  -- resizing
  {'nv', '<F2>K', '<C-w>+<C-w>+<C-w>+', { desc = 'Increase window height' }},
  {'nv', '<A-K>', '<C-w>+<C-w>+<C-w>+', { desc = 'Increase window height' }},
  {'nv', '<F2>J', '<C-w>-<C-w>-<C-w>-', { desc = 'Decrease window height' }},
  {'nv', '<A-J>', '<C-w>-<C-w>-<C-w>-', { desc = 'Decrease window height' }},
  {'nv', '<F2>H', '<C-w><<C-w><<C-w><', { desc = 'Decrease window width' }},
  {'nv', '<A-H>', '<C-w><<C-w><<C-w><', { desc = 'Decrease window width' }},
  {'nv', '<F2>L', '<C-w>><C-w>><C-w>>', { desc = 'Increase window width' }},
  {'nv', '<A-L>', '<C-w>><C-w>><C-w>>', { desc = 'Increase window width' }},
  -- zooming
  {'nC', '<C-w>s', 'lua Lpke_win_zoom_toggle()', { desc = '"Zoom" current window horizontally and vertically' }},
  {'nC', '<F2>s', 'lua Lpke_win_zoom_toggle()', { desc = 'Toggle current window "zoom" state' }},
  {'nC', '<A-s>', 'lua Lpke_win_zoom_toggle()', { desc = 'Toggle current window "zoom" state' }},
  {'n', '<F2>;', '<C-w>=', { desc = 'Equalise split windows' }},
  {'n', '<A-;>', '<C-w>=', { desc = 'Equalise split windows' }},

  -- tab control
  -- creation / deletion
  {'nC', '<C-w>c', 'tabnew', { desc = 'Create a new tab (blank file)' }},
  {'nC', '<C-w>C', 'tab split', { desc = 'Create a new tab (clone current buffer)' }},
  {'nC', '<C-w>n', 'tabnew', { desc = 'Create a new tab (blank file)' }},
  {'nC', '<C-w>N', 'tab split', { desc = 'Create a new tab (clone current buffer)' }},
  {'nC', '<C-w>&', 'tabclose', { desc = 'Close current tab' }},
  {'nC', '<F2>n', 'tabnew', { desc = 'Create a new tab (blank file)' }},
  {'nC', '<F2>N', 'tab split', { desc = 'Create a new tab (clone current buffer)' }},
  -- navigating
  {'nv', '<C-w><Right>', 'gt', { desc = 'Next Tab (right)' }},
  {'nv', '<C-w><Left>', 'gT', { desc = 'Previous Tab (left)' }},
  {'nviC', '<F2><Right>', 'tabnext', { desc = 'Next Tab (right)' }},
  {'nviC', '<A-Right>', 'tabnext', { desc = 'Next Tab (right)' }},
  {'nviC', '<F2><Left>', 'tabprevious', { desc = 'Previous Tab (left)' }},
  {'nviC', '<A-Left>', 'tabprevious', { desc = 'Previous Tab (left)' }},
  -- moving
  {'nC', '<C-w>g<Right>', 'tabmove +1', { desc = 'Move Tab Right' }},
  {'nC', '<C-w>g<Left>', 'tabmove -1', { desc = 'Move Tab Left' }},
  {'nC', '<M-S-Right>', 'tabmove +1', { desc = 'Move Tab Right' }},
  {'nC', '<M-S-Left>', 'tabmove -1', { desc = 'Move Tab Left' }},

  -- arrow-key scrolling
  {'nv', '<Down>', '4<C-e>', { desc = 'Scroll down (4 lines)' }},
  {'nv', '<Up>', '4<C-y>', { desc = 'Scroll up (4 lines)' }},
  {'nv', '<S-Right>', '6zl', { desc = 'Scroll right (6 columns)' }},
  {'nv', '<S-Left>', '6zh', { desc = 'Scroll left (6 columns)' }},

  -- center cursor when down/up page
  {'nv', '<C-u>', 'M<C-u>zz', { desc = 'Move up half a screen (center cursor)' }},
  {'nv', '<D-u>', 'M<C-u>zz', { desc = 'Move up half a screen (center cursor)' }},
  {'nv', '<C-d>', 'M<C-d>zz', { desc = 'Move down half a screen (center cursor)' }},
  {'nv', '<D-d>', 'M<C-d>zz', { desc = 'Move down half a screen (center cursor)' }},
  {'nv', '<C-Up>', 'M4kzz', { desc = 'Move up 4 line (center cursor)' }},
  {'nv', '<D-Up>', 'M4kzz', { desc = 'Move up 4 line (center cursor)' }},
  {'nv', '<C-Down>', 'M4jzz', { desc = 'Move down 4 line (center cursor)' }},
  {'nv', '<D-Down>', 'M4jzz', { desc = 'Move down 4 line (center cursor)' }},

  -- center cursor when searching
  {'n', 'n', 'nzzzv', { desc = 'Next search result (center cursor)' }},
  {'n', 'N', 'Nzzzv', { desc = 'Previous search result (center cursor)' }},

  -- horizontal mouse scrolling
  {'nv', '<S-ScrollWheelDown>', '6zl', { desc = 'Scroll right' }},
  {'nv', '<S-ScrollWheelUp>', '6zh', { desc = 'Scroll left' }},
  {'i', '<S-ScrollWheelDown>', '<Esc>6zl', { desc = 'Scroll right' }},
  {'i', '<S-ScrollWheelUp>', '<Esc>6zh', { desc = 'Scroll left' }},

  -- move selected code up/down
  {'v', 'J', [[:m '>+1<CR>gv=gv]], { desc = 'Move selected lines down' }},
  {'v', 'K', [[:m '<-2<CR>gv=gv]], { desc = 'Move selected lines up' }},

  -- wrapped line traversing
  {'nE', 'j', 'v:count ? "j" : "gj"', { desc = 'Move cursor down a line (works with wrapped lines)' }},
  {'nE', 'k', 'v:count ? "k" : "gk"', { desc = 'Move cursor up a line (works with wrapped lines)' }},

  -- keep current reg when pasting over selected text
  {'v', 'p', 'P', { desc = 'Paste (preserve " register)' }},
  {'v', 'P', 'p', { desc = 'Paste (default behavior)' }},

  -- repeatable multiline indentation
  {'v', '<', '<gv', { desc = 'Indent -1 level (repeatable)' }},
  {'v', '>', '>gv', { desc = 'Indent 1 level (repeatable)' }},

  -- include char under cursor when d/c/y backwards
  {'n', 'db', 'vbd', { desc = 'Delete b (including under cursor)' }},
  {'n', 'cb', 'vbc', { desc = 'Change b (including under cursor)' }},
  {'n', 'yb', 'vby', { desc = 'Yank b (including under cursor)' }},
  {'n', 'dB', 'vBd', { desc = 'Delete B (including under cursor)' }},
  {'n', 'cB', 'vBc', { desc = 'Change B (including under cursor)' }},
  {'n', 'yB', 'vBy', { desc = 'Yank B (including under cursor)' }},
  {'n', 'd^', 'v^d', { desc = 'Delete ^ (including under cursor)' }},
  {'n', 'c^', 'v^c', { desc = 'Change ^ (including under cursor)' }},
  {'n', 'y^', 'v^y', { desc = 'Yank ^ (including under cursor)' }},
  {'n', 'd0', 'v0d', { desc = 'Delete 0 (including under cursor)' }},
  {'n', 'c0', 'v0c', { desc = 'Change 0 (including under cursor)' }},
  {'n', 'y0', 'v0y', { desc = 'Yank 0 (including under cursor)' }},

  -- dont include surrounding whitespace in a'|a"|a` motions
  {'v', [[a']], [[2i']], { desc = [[Select outer ' (no whitespace)]] }},
  {'v', [[a"]], [[2i"]], { desc = [[Select outer " (no whitespace)]] }},
  {'v', [[a`]], [[2i`]], { desc = [[Select outer ` (no whitespace)]] }},
  {'n', [[da']], [[d2i']], { desc = [[Delete outer ' (no whitespace)]] }},
  {'n', [[da"]], [[d2i"]], { desc = [[Delete outer " (no whitespace)]] }},
  {'n', [[da`]], [[d2i`]], { desc = [[Delete outer ` (no whitespace)]] }},
  {'n', [[ca']], [[c2i']], { desc = [[Change outer ' (no whitespace)]] }},
  {'n', [[ca"]], [[c2i"]], { desc = [[Change outer " (no whitespace)]] }},
  {'n', [[ca`]], [[c2i`]], { desc = [[Change outer ` (no whitespace)]] }},
  {'n', [[ya']], [[y2i']], { desc = [[Yank outer ' (no whitespace)]] }},
  {'n', [[ya"]], [[y2i"]], { desc = [[Yank outer " (no whitespace)]] }},
  {'n', [[ya`]], [[y2i`]], { desc = [[Yank outer ` (no whitespace)]] }},

  -- find and replace
  {'nv', 'S', ''}, -- clear default S functionality
  {'n', 'SS', ':s/', { desc = 'Replace in current line' }},
  {'n', 'SF', ':%s/', { desc = 'Replace in current file' }},
  {'n', 'SV', [[:'<,'>s/\%V]], { desc = 'Replace in prev selection' }},
  {'v', 'SV', [[:s/\%V]], { desc = 'Replace in current selection' }},
  {'n', 'S**', [[:%s/\<<c-r><c-w>\>/<c-r><c-w>/gi<left><left><left>]],
    { desc = 'Replace under cursor (whole file)' }},
  {'n', 'S*v', [[:'<,'>s/\%V\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
    { desc = 'Replace under cursor (prev selection)' }},
  {'n', 'S*V', [[:'<,'>s/\%V\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
    { desc = 'Replace under cursor (prev selection)' }},
})

-- yank still: prevent cursor movement after yanking
helpers.keymap_set_yank_still_upwards(100)
helpers.keymap_set_yank_still_marks()

-- convert windows line endings to unix when pasting from global registers
if helpers.is_wsl then
  keymap_set({'nv!', '"*p', function() helpers.paste_unix('*') end,
    { desc = 'Paste from * register (converting to unix line endings)' }})
  keymap_set({'nv!', '"+p', function() helpers.paste_unix('+') end,
    { desc = 'Paste from + register (converting to unix line endings)' }})
  keymap_set({'nv!', '<leader>p', function() helpers.paste_unix('*') end,
    { desc = 'Paste from * register (converting to unix line endings)' }})
  keymap_set({'nv!', '<leader>P', function() helpers.paste_unix('*', true) end,
    { desc = 'Paste to line above from * register (converting to unix line endings)' }})
else
  keymap_set({'nv', '<leader>p', '"*p', { desc = 'Global paste' }})

end
-- stylua: ignore end

-- disabling shortcuts of :read to prevent accidental activation when typing :reg
vim.cmd('cabbrev r echo "shorthand for :read disabled"')
vim.cmd('cabbrev re echo "shorthand for :read disabled"')
vim.cmd('cabbrev rea echo "shorthand for :read disabled"')
