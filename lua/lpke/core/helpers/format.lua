---@class lpke.core.helpers.format
local M = {}

local util = require('lpke.core.helpers.util')

-- remove the protocol (eg `oil://` or `oil-trash://`) from a string
function M.remove_protocol(str)
  return str:gsub('^.*://', '')
end

function M.get_path_protocol(path)
  local protocol = path:match('^(.-)://')
  if protocol then
    return protocol
  end
  return nil
end

-- get last segment of a path
function M.get_path_tail(str, include_trailing_slash)
  if include_trailing_slash then
    return str:match('([^/]+/?/?)$')
  else
    return str:match('([^/]+)/?/?$')
  end
end

-- get cwd folder name
function M.get_cwd_folder()
  local cwd = vim.fn.getcwd()
  return M.get_path_tail(cwd)
end

-- get extension of last segment of a path
function M.get_path_extension(path)
  local tail = M.get_path_tail(path)
  if not tail or tail == '' then
    return nil
  end
  return tail:match('%.([^%.]+)$')
end

-- get filename of a path (nil if no extension)
function M.get_path_filename(path, include_ext)
  local tail = M.get_path_tail(path)
  local file_ext = M.get_path_extension(path)
  if not file_ext then
    return nil
  end
  if include_ext then
    return tail
  else
    local filename = tail:match('^(.+)%.[^%.]*$')
    return filename or tail
  end
end

function M.shorten_path(path, shorten_tail)
  local simple_paths = { '', '/', '~', '~/', '.', './' }
  for _, simple_path in ipairs(simple_paths) do
    if path == simple_path then
      return path
    end
  end

  local has_leading_slash = Char(path, 1) == '/'
  local has_trailing_slash = Char(path, -1) == '/'

  -- get path segments
  local segments = {}
  local path_no_trail_slash = has_trailing_slash and path:sub(1, -2) or path
  for segment in path_no_trail_slash:gmatch('[^/]+') do
    table.insert(segments, segment)
  end

  if not shorten_tail and #segments <= 1 then
    return path
  end

  -- shorten all segments
  local shortened_segments = {}
  for _, segment in ipairs(segments) do
    local shortened = nil
    -- separate leading special chars from first normal (alphanumeric) char
    local special_chars, first_normal_char = segment:match('^([^%w]*)(%w)')
    local special_chars_valid = type(special_chars) == 'string'
      and #special_chars > 0
    local first_normal_char_valid = type(first_normal_char) == 'string'
      and #first_normal_char == 1
    -- handle shortening logic
    if special_chars_valid and first_normal_char_valid then
      if #special_chars <= 2 then
        shortened = special_chars .. first_normal_char
      else
        shortened = special_chars:sub(1, 1) .. '…' .. first_normal_char
      end
    else
      shortened = Char(segment, 1)
    end
    table.insert(shortened_segments, shortened or Char(segment, 1))
  end

  local last_full_segment = segments[#segments]
  local last_shortened_segment = shortened_segments[#shortened_segments]
  table.remove(shortened_segments, #shortened_segments)

  -- reconstruct path
  local result = ''
  if shorten_tail then
    local file_ext = M.get_path_extension(last_full_segment)
    if not file_ext then
      result = table.concat(shortened_segments, '/')
        .. '/'
        .. last_shortened_segment
    else
      result = table.concat(shortened_segments, '/')
        .. '/'
        .. last_shortened_segment
        .. '….'
        .. file_ext
    end
  else
    result = table.concat(shortened_segments, '/') .. '/' .. last_full_segment
  end

  -- add back leading/trailing slashes if applicable
  if has_leading_slash then
    result = '/' .. result
  end
  if has_trailing_slash then
    result = result .. '/'
  end

  return result
end

-- parse and return path segments and info (no formatting)
function M.parse_path(path)
  local P = {}
  P.orig_path = path
  P.protocol = M.get_path_protocol(path)
  path = M.remove_protocol(path)

  P.path_full = path
  P.tail_full = M.get_path_tail(path, true)
  P.tail = M.get_path_tail(path)
  P.filename_full = M.get_path_filename(path, true)
  P.filename = M.get_path_filename(path, false)
  P.extension = M.get_path_extension(path)
  P.path_without_tail = path:match('^(.*/)[^/]+/?$') or path
  P.path_without_file = path:gsub(P.full_filename or '', '')

  P.is_file = M.get_path_extension(path) ~= nil
  P.is_dir = M.get_path_extension(path) == nil

  P.has_leading_slash = Char(path, 1) == '/'
  P.has_trailing_slash = Char(path, -1) == '/'
  return P
end

-- adds/removes leading/trailing slashes
---@param path string
---@param format string String to represent desired output format.
---  `.` = path
---  `/` = add slash (omit for remove)
---  `?` = leave as-is (with or without slash)
---  eg: `/./`, `?./`, `./`, `.`
---@return string
function M.path_surround_slash(path, format)
  local result = path

  -- safety checks
  if not Match(format, '%.') then
    vim.notify(
      'path_surround_slash: format must contain at least one `.` character',
      vim.log.levels.ERROR
    )
    return path
  end
  if Match(format, '[^./?]') then
    vim.notify(
      'path_surround_slash: format can only contain `.`, `?`, `/` characters',
      vim.log.levels.ERROR
    )
    return path
  end
  if #format > 3 then
    vim.notify(
      'path_surround_slash: format can only be up to 3 characters long',
      vim.log.levels.ERROR
    )
    return path
  end

  -- leading slash
  local leading_format_char = Char(format, 1)
  local has_leading_slash = Char(result, 1) == '/'
  if leading_format_char == '/' then
    if not has_leading_slash then
      result = '/' .. result
    end
  elseif leading_format_char == '.' then
    if has_leading_slash then
      result = result:sub(2)
    end
  end

  -- trailing slash
  local trailing_format_char = format:sub(-1)
  local has_trailing_slash = Char(result, -1) == '/'
  if trailing_format_char == '/' then
    if not has_trailing_slash then
      result = result .. '/'
    end
  elseif trailing_format_char == '.' then
    if has_trailing_slash then
      result = result:sub(1, -2)
    end
  end

  return result
end

---Transform full path string to a configurable path.
---@param full_path string The full path to transform
---@param opts? { relative?: boolean, include_filename?: boolean, dir_tail_slash?: boolean, cwd_name?: boolean, shorten?: boolean, shorten_tail?: boolean } Options table
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
    shorten_tail = false,
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
    path = M.shorten_path(path, opts.shorten_tail)
  end

  if
    opts.dir_tail_slash
    and (not opts.include_filename or not M.get_path_extension(path))
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
