-- changes working directory to <target_path> for <target_scope ('global'|'tab'|'window')>
-- returns final working directory as string
function Lpke_cd(target_path, target_scope)
  -- TODO
  -- get a path and scope from the targets or fall back on defaults
  -- use `find_upward_to_git_root_or_cwd` or `Lpke_find_git_root`
  -- use this to replace the `cd()` function in the oil config

  -- local path = 
  -- if path == nil or path == '' then
  -- end

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
