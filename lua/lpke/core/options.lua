local E = {}
local helpers = require('lpke.core.helpers')

--------------------------
-- CUSTOM OPTIONS
--------------------------

E.custom_opts = {
  symbols = {
    modified = '●',
    modified_alt = '○',
    readonly = '',
    unnamed = '[No Name]',
    newfile = '[New]',
  },
}

--------------------------
-- VIM OPTIONS
--------------------------

E.vim_opts = {
  backup = false, -- no backups (using persistent undo instead)
  swapfile = false, -- don't create a swapfile (using persistent undo instead)
  -- TODO: handle windows check in seperate function as well as path handling
  undodir = (function()
    if vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
      -- Windows: use LOCALAPPDATA or fallback to USERPROFILE
      local localappdata = os.getenv('LOCALAPPDATA')
      if localappdata then
        return localappdata .. '\\nvim\\undo'
      else
        return os.getenv('USERPROFILE') .. '\\AppData\\Local\\nvim\\undo'
      end
    else
      -- Unix-like systems (macOS, Linux, WSL)
      return os.getenv('HOME') .. '/.local/share/nvim/undo'
    end
  end)(), -- where undo files are saved
  undofile = true, -- use persistent undo (persists sessions)
  clipboard = '', -- setting this to anything else will make pasting very slow on WSL
  cmdheight = 1, -- set height of command-line to 1
  conceallevel = 0, -- show text normally
  more = false, -- dont steal focus for console messages
  --fileencoding = 'utf-8', -- file encoding for current buffer
  hlsearch = false, -- don't highlight matches
  incsearch = true, -- show the pattern matches as i type
  mouse = 'a', -- enable mouse for all modes (including commands)
  --pumheight = 5, -- set the popup menu height to 10
  termguicolors = true, -- enables 24-bit color in tui
  splitbelow = true, -- open new horizontal splits below current buffer
  splitright = true, -- open new vertical splits to the right of current buffer
  number = true, -- set line numbers, this setting shows the line number you're currently on
  relativenumber = true, -- make the line numbers relative to active line
  numberwidth = 4, -- the width of the number column
  signcolumn = 'yes', -- show signs in signcolumn
  wrap = false, -- line wrap
  breakindent = true, -- wrapped text is indented to that line's indent level
  laststatus = 3, -- last window has status line - 0:never, 1:only if 2+ wins, 2: always, 3: always and only last win (global)
  tabstop = 2, -- maximum width of an actual tab character
  softtabstop = 2, -- number of spaces a tab counts for during editing operations
  shiftwidth = 2, -- the size of code indents
  textwidth = 80, -- width that `gw/gq` will target when wrapping text
  expandtab = true, -- always expand tab to spaces
  smarttab = true, -- tab inserts whitespace only to the next predefined tab stop
  shiftround = true, -- when indenting, stop at next shiftwidth (don't end up in between stops)
  guicursor = 'n-v-c-sm-o:block,i-ci-ve:ver25,r-cr:hor20', -- cursor style for different modes
  --shellxquote = '', -- i can use this to do cool things
  autoindent = true, -- this should absolutely always be on
  smartindent = true, -- so should this.
  scrolloff = 6, -- minumum number of lines to keep above/below cursor
  sidescrolloff = 6, -- minumum number of char columns to keep left/right of cursor
  equalalways = false, -- dont force windows to be equal after opening/closing
  ignorecase = true, -- ignore case of letters when searching (see also \c)
  smartcase = true, -- dont ignore case if search contains capitals (see also \C)
  cursorline = false, -- render cursor line background/line number highlights (slower)
  shada = "!,'500,<500,s100,h", -- things to save to "shared data" file
  jumpoptions = 'view', -- try and remember view position when jumping
  shortmess = 'filnxtToOFI', -- default up until 'I' (disabling welcome message)
  listchars = [[tab:» ,trail:·,nbsp:·,extends:>,precedes:<]], -- whitespace chars to show when `list` option is toggled on
  statusline = ' %f %m %= %l:%c ', -- TODO: add percent, other useful stuff
  sessionoptions = 'blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions',
  formatoptions = 'jql', -- see `:help fo-table` (I removed 'c' to disable auto-wrap, use gw motion instead)
  timeoutlen = 4000, -- timeout when waiting for next key in a keymap
  tabline = '%!v:lua.Lpke_tabline()',
}
helpers.set_options(E.vim_opts)

--------------------------
-- GLOBAL VARIABLES
--------------------------

-- wsl clipboard support
if helpers.is_wsl then
  vim.g.clipboard = {
    name = 'WslClipboard',
    copy = {
      ['+'] = 'clip.exe',
      ['*'] = 'clip.exe',
    },
    paste = {
      ['+'] = 'powershell.exe Get-Clipboard',
      ['*'] = 'powershell.exe Get-Clipboard',
    },
    cache_enabled = 1,
  }
end

-- netrw
vim.g.netrw_banner = 0

--------------------------
-- AUTOCOMMANDS
--------------------------

-- disable next line auto-comment
vim.cmd('autocmd FileType * set formatoptions-=cro')

-- toggle diagnostics when going enter/leave insert mode
Lpke_diagnostics_insert_disabled = nil
vim.api.nvim_create_autocmd('InsertEnter', {
  pattern = '*',
  callback = function()
    Lpke_diagnostics_insert_disabled = true
    Lpke_toggle_diagnostics(false)
  end,
})
vim.api.nvim_create_autocmd('InsertLeave', {
  pattern = '*',
  callback = function()
    if Lpke_diagnostics_insert_disabled then
      Lpke_toggle_diagnostics(Lpke_diagnostics_enabled_prev)
      Lpke_diagnostics_insert_disabled = false
    end
  end,
})

-- remember folds
-- vim.api.nvim_create_autocmd({"BufWinLeave"}, {
--   pattern = {"*.*"},
--   desc = "Save view (folds) when closing file",
--   command = "mkview",
-- })
-- vim.api.nvim_create_autocmd({"BufWinEnter"}, {
--   pattern = {"*.*"},
--   desc = "load view (folds) when opening file",
--   command = "silent! loadview"
-- })

-- disable matchparen in insert mode
-- local matchparen_group =
--   vim.api.nvim_create_augroup('MatchParenToggle', { clear = true })
-- vim.api.nvim_create_autocmd('InsertEnter', {
--   group = matchparen_group,
--   pattern = '*',
--   callback = function()
--     if
--       vim.bo.filetype ~= 'TelescopePrompt' and vim.fn.getcmdwintype() == ''
--     then
--       vim.cmd('NoMatchParen')
--     end
--   end,
-- })
-- vim.api.nvim_create_autocmd('InsertLeave', {
--   group = matchparen_group,
--   pattern = '*',
--   callback = function()
--     if
--       vim.bo.filetype ~= 'TelescopePrompt' and vim.fn.getcmdwintype() == ''
--     then
--       vim.cmd('DoMatchParen')
--     end
--   end,
-- })

--------------------------
-- USER COMMANDS
--------------------------

Lpke_messages_win_open = false
Lpke_messages_win_id = nil
Lpke_messages_buf_id = nil
-- stylua: ignore start
vim.api.nvim_create_user_command('Bclean', Lpke_clean_buffers, {})

-- terminal
vim.api.nvim_create_user_command('TrashRestore', Lpke_trash_restore, {})
vim.api.nvim_create_user_command('T', Lpke_term, { nargs = '*' }) -- arg: full
vim.api.nvim_create_user_command('Term', Lpke_term, { nargs = '*' }) -- arg: full
vim.api.nvim_create_user_command('Terminal', Lpke_term, { nargs = '*' }) -- arg: full
vim.api.nvim_create_user_command('R', Lpke_ranger, { nargs = '*' }) -- arg: full
vim.api.nvim_create_user_command('Ranger', Lpke_ranger, { nargs = '*' }) -- arg: full

-- message window
vim.api.nvim_create_user_command('M', Lpke_toggle_messages, { desc = 'Open :messages in a bottom split' })
vim.api.nvim_create_user_command('Mes', Lpke_toggle_messages, { desc = 'Open :messages in a bottom split' })
vim.api.nvim_create_user_command('Messages', Lpke_toggle_messages, { desc = 'Open :messages in a bottom split' })

-- printing
vim.api.nvim_create_user_command('P', function(cmd)
  if #cmd.fargs == 0 then
    print('PP: buf name | PC: cwd | PG: git root | PW: win details | P <args>: Lpke_print(...args)')
  else
    local args = helpers.parse_command_args(cmd.fargs)
    Lpke_print(table.unpack(args))
  end
end, { nargs = '*', desc = 'Print help for `P` commands or call Lpke_print with args' })
vim.api.nvim_create_user_command('PP', function() print(helpers.get_buf_name()) end, { desc = 'Print the active buffer name' })
vim.api.nvim_create_user_command('PC', function() print(vim.fn.getcwd()) end, { desc = 'Print the current working directory' })
vim.api.nvim_create_user_command('PG', function() Lpke_git_root() end, { desc = 'Print the path of the git root of the current file' })
vim.api.nvim_create_user_command('PW', Lpke_active, { desc = 'Print details about the currently active tab/buffer/window' })

-- yanking
vim.api.nvim_create_user_command('Y', function() print('YP/p: buf name | YD/d: cwd | YG/g: git root | YL/l: location | YT/t: tab ID | YB/b: buf ID | YW/w: win ID') end,
  { desc = 'Print help for `Y` commands' })
vim.api.nvim_create_user_command('YP', function(cmd) Lpke_yank_buf_name(cmd, true) end, { nargs = '*' }) -- arg: <register>
vim.api.nvim_create_user_command('Yp', function(cmd) Lpke_yank_buf_name(cmd, false) end, { nargs = '*' }) -- arg: <register>
vim.api.nvim_create_user_command('YC', function(cmd) Lpke_yank_cwd(cmd, true) end, { nargs = '*' }) -- arg: <register>
vim.api.nvim_create_user_command('Yc', function(cmd) Lpke_yank_cwd(cmd, false) end, { nargs = '*' }) -- arg: <register>
vim.api.nvim_create_user_command('YG', function(cmd) Lpke_yank_git_root(cmd, true) end, { nargs = '*' }) -- arg: <register>
vim.api.nvim_create_user_command('Yg', function(cmd) Lpke_yank_git_root(cmd, false) end, { nargs = '*' }) -- arg: <register>
vim.api.nvim_create_user_command('YL', function(cmd) Lpke_yank_location(cmd, true) end, { nargs = '*' }) -- arg: <register> ['blame']
vim.api.nvim_create_user_command('Yl', function(cmd) Lpke_yank_location(cmd, false) end, { nargs = '*' }) -- arg: <register> ['blame']
vim.api.nvim_create_user_command('YT', function(cmd) Lpke_yank_tab_id(cmd, true) end, { nargs = '*' }) -- arg: <register>
vim.api.nvim_create_user_command('Yt', function(cmd) Lpke_yank_tab_id(cmd, false) end, { nargs = '*' }) -- arg: <register>
vim.api.nvim_create_user_command('YB', function(cmd) Lpke_yank_buf_id(cmd, true) end, { nargs = '*' }) -- arg: <register>
vim.api.nvim_create_user_command('Yb', function(cmd) Lpke_yank_buf_id(cmd, false) end, { nargs = '*' }) -- arg: <register>
vim.api.nvim_create_user_command('YW', function(cmd) Lpke_yank_win_id(cmd, true) end, { nargs = '*' }) -- arg: <register>
vim.api.nvim_create_user_command('Yw', function(cmd) Lpke_yank_win_id(cmd, false) end, { nargs = '*' }) -- arg: <register>
-- stylua: ignore end

return E
