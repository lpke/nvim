local M = {}
local helpers = require('lpke.core.helpers')

--------------------------
-- CUSTOM OPTIONS
--------------------------

M.custom_opts = {
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

M.vim_opts = {
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
  ttimeoutlen = 0, -- no delay after <esc> to interpret it as <alt>
  tabline = '%!v:lua.Lpke_tabline()',
}
helpers.set_options(M.vim_opts)

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

return M
