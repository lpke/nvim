local M = {}

local helpers = require('lpke.core.helpers')

local HELP_TAG = 'lpke-help'
local DOC_DIR = vim.fn.stdpath('config') .. '/doc'
local DOC_FILE = DOC_DIR .. '/lpke-help.txt'
local TAG_FILE = DOC_DIR .. '/tags'

local function normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

local function is_custom_help_buf(bufnr)
  return normalize(vim.api.nvim_buf_get_name(bufnr)) == normalize(DOC_FILE)
end

local function helptags_stale()
  local doc_mtime = vim.fn.getftime(DOC_FILE)
  local tag_mtime = vim.fn.getftime(TAG_FILE)

  return doc_mtime > 0 and tag_mtime < doc_mtime
end

local function generate_helptags()
  if vim.fn.filereadable(DOC_FILE) ~= 1 then
    vim.notify('Custom help file not found: ' .. DOC_FILE, vim.log.levels.ERROR)
    return false
  end

  local ok, err =
    pcall(vim.cmd, 'silent helptags ' .. vim.fn.fnameescape(DOC_DIR))
  if not ok then
    vim.notify(
      'Failed to generate custom helptags: ' .. err,
      vim.log.levels.ERROR
    )
    return false
  end

  return true
end

local function ensure_helptags()
  if helptags_stale() then
    return generate_helptags()
  end

  return true
end

local function configure_win()
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = 'no'
  vim.wo.foldcolumn = '0'
  vim.wo.spell = false
  vim.wo.list = false
  vim.wo.wrap = false
  vim.wo.cursorline = true

  local target_height =
    math.min(32, math.max(18, math.floor(vim.o.lines * 0.5)))
  pcall(vim.api.nvim_win_set_height, 0, target_height)
end

local function tag_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1

  for start_col, tag, end_col in line:gmatch('()|([^|]+)|()') do
    if col >= start_col and col <= end_col then
      return tag
    end
  end
end

local function jump_to_help_tag()
  local tag = tag_under_cursor()
  if tag and tag ~= '' then
    vim.cmd('help ' .. tag)
  end
end

local function configure_buf(bufnr)
  if not is_custom_help_buf(bufnr) then
    return
  end

  vim.bo[bufnr].buflisted = false

  helpers.keymap_set_multi({
    {
      'n',
      'q',
      '<cmd>close<cr>',
      { buffer = bufnr, desc = 'Close custom help' },
    },
    {
      'n',
      '<CR>',
      jump_to_help_tag,
      { buffer = bufnr, desc = 'Jump to help tag' },
    },
    {
      'n',
      'gO',
      '<cmd>help lpke-contents<cr>',
      { buffer = bufnr, desc = 'Go to custom help contents' },
    },
  })
end

local group = vim.api.nvim_create_augroup('LpkeCustomHelp', { clear = true })

vim.api.nvim_create_autocmd('BufWritePost', {
  group = group,
  pattern = DOC_FILE,
  desc = 'Regenerate custom help tags',
  callback = generate_helptags,
})

vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
  group = group,
  pattern = DOC_FILE,
  desc = 'Configure custom help buffer',
  callback = function(event)
    configure_buf(event.buf)
    configure_win()
  end,
})

function M.open()
  if not ensure_helptags() then
    return
  end

  vim.cmd('botright help ' .. HELP_TAG)
  configure_buf(vim.api.nvim_get_current_buf())
  configure_win()
end

return M
