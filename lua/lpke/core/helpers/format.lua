---@class lpke.core.helpers.format
local M = {}

local util = require('lpke.core.helpers.util')

M.is_wsl = vim.fn.exists('$WSL_DISTRO_NAME') == 1

-- get current session name
function M.get_session_name(fallback)
  return util.safe_call(
    require('auto-session.lib').current_session_name,
    true,
    fallback
  )
end

-- get buf name (current if omitted), which is usually the path
function M.get_buf_name(bufnr, remove_protocol)
  bufnr = bufnr or 0
  local raw_buf_name = vim.api.nvim_buf_get_name(bufnr)
  local buf_name = remove_protocol and M.remove_protocol(raw_buf_name)
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

-- get last segment of a path
function M.get_path_tail(str)
  return str:match('([^/]+/?/?)$')
end

-- get cwd folder name
function M.get_cwd_folder()
  local cwd = vim.fn.getcwd()
  return M.get_path_tail(cwd)
end

-- remove the protocol (eg `oil://` or `oil-trash://`) from a string
function M.remove_protocol(str)
  return str:gsub('^.*://', '')
end

-- shorten a path (eg `plugins/lsp/test.lua` to `p/l/test.lua`)
function M.shorten_path(path)
  return path:gsub('([^/%w]?[^/])[^/]*/', '%1/')
end

-- transform full path string to a configurable relative path
function M.transform_path(full_path, opts)
  full_path = M.remove_protocol(full_path)
  opts = opts or {}
  local default_opts = {
    include_filename = true,
    dir_tail_slash = true,
    cwd_name = true,
    shorten = false,
  }
  opts = util.merge_tables(default_opts, opts)

  local mods = ':p:~:.' .. (opts.include_filename and '' or ':h')
  local rel_path = vim.fn.fnamemodify(full_path, mods)

  if opts.cwd_name and rel_path == '.' then
    rel_path = M.get_cwd_folder()
  end

  if opts.shorten then
    rel_path = M.shorten_path(rel_path)
  end

  if
    opts.dir_tail_slash
    and not opts.include_filename
    and (string.sub(rel_path, -1) ~= '/')
  then
    rel_path = rel_path .. '/'
  end

  return rel_path
end

-- return path of first file/dir matching item in `items` if it exists under git root or cwd
---@param items string[] -- list of items (file or dirs) to search for
---@return string | nil
function M.find_file_upward(items)
  local cur_dir = vim.fn.fnamemodify(vim.fn.expand('%:p'), ':h')
  local root = Lpke_find_git_root() or vim.fn.getcwd()
  while cur_dir and cur_dir ~= '/' do
    for _, item in ipairs(items) do
      local path
      if item:sub(-1) == '/' then
        -- item is a directory
        path = cur_dir .. '/' .. item:sub(1, -2)
        if vim.fn.isdirectory(path) == 1 then
          return path .. '/'
        end
      else
        -- item is a file
        path = cur_dir .. '/' .. item
        if vim.fn.filereadable(path) == 1 then
          return path
        end
      end
    end
    if cur_dir == root then
      break
    end
    local parent = vim.fn.fnamemodify(cur_dir, ':h')
    if parent == cur_dir then
      break
    end
    cur_dir = parent
  end
  return nil
end

-- check if session exists and matches cwd
function M.session_in_cwd()
  local cwd = M.get_cwd_folder()
  local session = M.get_session_name()
  return session and not (cwd == session)
end

return M
