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

-- shorten a path (eg `plugins/lsp/test.lua` to `p/l/test.lua`)
function M.shorten_path(path)
  return path:gsub('([^/%w]?[^/])[^/]*/', '%1/')
end

-- check if path has an extension
function M.path_has_extension(path)
  local tail = M.get_path_tail(path)
  return tail and Match(tail, '%.[^/]*$')
end

---Transform full path string to a configurable path.
---@param full_path string The full path to transform
---@param opts? { relative?: boolean, include_filename?: boolean, dir_tail_slash?: boolean, cwd_name?: boolean, shorten?: boolean } Options table
---@return string path The transformed path
function M.transform_path(full_path, opts)
  full_path = M.remove_protocol(full_path)
  opts = opts or {}
  local default_opts = {
    relative = true,
    include_filename = true,
    dir_tail_slash = true,
    cwd_name = true,
    shorten = false,
  }
  opts = util.merge_tables(default_opts, opts)

  local mods = ':p:~'
    .. (opts.relative and ':.' or '')
    .. (opts.include_filename and '' or ':h')
  local path = vim.fn.fnamemodify(full_path, mods)

  if opts.cwd_name and path == '.' then
    path = M.get_cwd_folder()
  end

  if opts.shorten then
    path = M.shorten_path(path)
  end

  if
    opts.dir_tail_slash
    and (not opts.include_filename or not M.path_has_extension(path))
    and (Char(path, -1) ~= '/')
  then
    path = path .. '/'
  end

  return path
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
