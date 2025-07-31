---@class lpke.core.helpers.info
local M = {}

local util = require('lpke.core.helpers.util')
local format = require('lpke.core.helpers.format')

M.is_wsl = vim.fn.exists('$WSL_DISTRO_NAME') == 1

-- get current session name
function M.get_session_name(fallback)
  return util.safe_call(
    require('auto-session.lib').current_session_name,
    true,
    fallback
  )
end

-- check if session exists and matches cwd
function M.session_in_cwd()
  local cwd = format.get_cwd_folder()
  local session = M.get_session_name()
  return session and not (cwd == session)
end

-- get buf name (current if omitted), which is usually the path
function M.get_buf_name(bufnr, remove_protocol)
  bufnr = bufnr or 0
  local raw_buf_name = vim.api.nvim_buf_get_name(bufnr)
  local buf_name = remove_protocol and format.remove_protocol(raw_buf_name)
    or raw_buf_name
  return buf_name
end

-- get buf file type (current if omitted)
function M.get_file_type(bufnr)
  bufnr = bufnr or 0
  return vim.api.nvim_get_option_value('filetype', { buf = bufnr })
end

-- get buftype option
function M.get_buf_type(bufnr)
  bufnr = bufnr or 0
  return vim.api.nvim_get_option_value('buftype', { buf = bufnr })
end

-- returns a string of the git handler or nil if not a git buffer
---@param bufnr integer|nil
---@return 'git'|'fugitive'|'diffview'|'gitsigns'|nil
function M.get_git_buf_type(bufnr)
  if not bufnr then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local buf_name = M.get_buf_name(bufnr)
  local file_type = M.get_file_type(bufnr)

  local git_buffer = vim.tbl_contains(
    { 'git', 'gitcommit', 'gitui', 'gitmerge', 'gitrebase' },
    file_type
  ) or Match(buf_name, '^git://') or Match(buf_name, '^git://')
  local fugitive_buffer = Match(file_type, 'fugitive')
    or Match(buf_name, '^fugitive://')
  local diffview_buffer = Match(file_type, 'Diffview')
    or Match(buf_name, '^diffview://')
  local gitsigns_buffer = Match(file_type, 'gitsigns')
    or Match(buf_name, '^gitsigns%-.+://')

  if git_buffer then
    return 'git'
  elseif fugitive_buffer then
    return 'fugitive'
  elseif diffview_buffer then
    return 'diffview'
  elseif gitsigns_buffer then
    return 'gitsigns'
  end
  return nil
end

-- returns a string of the oil "buffer type" or nil if not oil
---@param bufnr integer|nil
---@return 'oil'|'trash'|nil
function M.get_oil_buf_type(bufnr)
  if not bufnr then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local buf_name = M.get_buf_name(bufnr)
  local file_type = M.get_file_type(bufnr)

  local oil_buffer = vim.tbl_contains({ 'oil' }, file_type)
    or Match(buf_name, '^oil://')
  local oil_trash_buffer = Match(buf_name, '^oil%-trash://')

  if oil_trash_buffer then
    return 'trash'
  elseif oil_buffer then
    return 'oil'
  end
  return nil
end

---Get custom "buf type" from buftype opt and custom conditions
---Custom types that differ from `vim.bo.buftype`:
---  buftype '': `normal`
---  takes priority over buftype: `git`, `oil`, `codecompanion`
---@return 'normal'|'git_git'|'git_fugitive'|'git_diffview'|'git_gitsigns'|'oil_oil'|'oil_trash'|'codecompanion'|'acwrite'|'help'|'nofile'|'nowrite'|'quickfix'|'terminal'|'prompt'
function M.get_custom_buf_type(bufnr)
  bufnr = bufnr or 0

  local buf_type_opt = M.get_buf_type(bufnr)
  local file_type = M.get_file_type(bufnr)
  local git_buf_type = M.get_git_buf_type(bufnr)
  local oil_buf_type = M.get_oil_buf_type(bufnr)

  if git_buf_type then
    return 'git_' .. git_buf_type
  end
  if oil_buf_type then
    return 'oil_' .. oil_buf_type
  end
  -- TODO: create a file type map?
  if file_type == 'codecompanion' then
    return 'codecompanion'
  end
  if buf_type_opt == '' then
    return 'normal'
  end
  return buf_type_opt
end

return M
