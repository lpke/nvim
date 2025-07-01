-- checks if a path string is valid and exists in the filesystem
-- path can be relative or absolute
function Lpke_path_exists(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil
end

-- changes working directory to <target_path> for <target_scope ('global'|'tab'|'window')>
-- returns final working directory as string
function Lpke_cd(target_path, target_scope)
  -- TODO
  -- get a path and scope from the targets or fall back on defaults
  -- use this to replace the `cd()` function in the oil config

  -- default path and scope if not provided or invalid
  local path = Lpke_find_git_root() or vim.fn.getcwd()
  local scope = 'global'
  print(path)
  print(scope)
  if type(target_path) == 'string' and Lpke_path_exists(target_path) then
    path = target_path
  else
    vim.notify(
      'Lpke_cd: Invalid target_path provided, using current working directory.',
      vim.log.levels.WARN
    )
  end

  -- buffer type safety check
  local normal_buffer = vim.bo.buftype == ''
  local oil_buffer = vim.bo.filetype == 'oil'
  if not (normal_buffer or oil_buffer) then
    vim.notify(
      'Lpke_cd: Cannot cd - not in normal or oil buffer.',
      vim.log.levels.WARN
    )
    return vim.fn.getcwd()
  end

  local cur_dir = nil
  if oil_buffer then
    cur_dir = require('oil').get_current_dir()
  else
    cur_dir = vim.fn.expand('%:p:h') .. '/'
  end

  return vim.fn.getcwd()
end
