---@class lpke.core.helpers.format
local M = {}

local util = require('lpke.core.helpers.util')

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

-- get buf name (current if omitted), which is usually the path
function M.get_buf_name(bufnr, remove_protocol)
  bufnr = bufnr or 0
  local raw_buf_name = vim.api.nvim_buf_get_name(bufnr)
  local buf_name = remove_protocol and M.remove_protocol(raw_buf_name)
    or raw_buf_name
  return buf_name
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

return M
