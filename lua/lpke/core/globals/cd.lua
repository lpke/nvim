---Checks if a path string is valid and exists in the filesystem
---@param path string The path to check (can be relative or absolute)
---@return boolean # True if the path exists, false otherwise
function Lpke_path_exists(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil
end

---Changes working directory to a target path for a target scope
---@param target_path string? The target directory path
---@param target_scope "global"|"tab"|"window"? The scope for the directory change
---@param log boolean? Whether to log the change
---@return string # The final working directory
function Lpke_cd(target_path, target_scope, log)
  -- default path and scope if not provided or invalid
  local path = Lpke_find_git_root(vim.fn.getcwd(-1, -1))
    or vim.fn.getcwd(-1, -1)
  local scope = 'global'
  if type(target_path) == 'string' and Lpke_path_exists(target_path) then
    path = target_path
  else
    -- assume empty string means deliberately go to root
    if target_path ~= '' then
      vim.notify(
        'Lpke_cd: Invalid target_path provided. Using: ' .. path,
        vim.log.levels.WARN
      )
    end
  end
  if type(target_scope) == 'string' then
    if
      target_scope == 'global'
      or target_scope == 'tab'
      or target_scope == 'window'
    then
      scope = target_scope
    else
      vim.notify(
        'Lpke_cd: Invalid target_scope provided. Using: ' .. scope,
        vim.log.levels.WARN
      )
    end
  end

  -- change directory
  if scope == 'global' then
    vim.cmd('cd ' .. path)
  elseif scope == 'tab' then
    vim.cmd('tcd ' .. path)
  elseif scope == 'window' then
    vim.cmd('lcd ' .. path)
  end

  pcall(function()
    require('lualine').refresh()
  end)
  if log then
    vim.notify(
      scope:upper()
        .. ' working dir set to: '
        .. vim.fn.fnamemodify(vim.fn.getcwd(), ':p'),
      vim.log.levels.INFO
    )
  end
  return vim.fn.getcwd()
end

---Changes working directory to current directory for a target scope
---@param scope "global"|"tab"|"window"? The scope for the directory change
---@param log boolean? Whether to log the change
---@return string # The final working directory
function Lpke_cd_here(scope, log)
  -- buffer type safety check
  local normal_buffer = vim.bo.buftype == ''
  local oil_buffer = vim.bo.filetype == 'oil'
  if not (normal_buffer or oil_buffer) then
    vim.notify(
      'Lpke_cd_here: Cannot cd - not in normal or oil buffer.',
      vim.log.levels.WARN
    )
    return vim.fn.getcwd()
  end

  -- get current directory
  local cur_dir = nil
  if oil_buffer then
    cur_dir = require('oil').get_current_dir()
  else
    cur_dir = vim.fn.expand('%:p:h') .. '/'
  end

  -- ensure current directory is valid
  if not Lpke_path_exists(cur_dir) then
    vim.notify(
      'Lpke_cd_here: Directory invalid: ' .. cur_dir,
      vim.log.levels.ERROR
    )
    return vim.fn.getcwd()
  end

  Lpke_cd(cur_dir, scope, log)
  return vim.fn.getcwd()
end

---Changes working directory to git root (or fallback) for a target scope
---@param scope "global"|"tab"|"window"? The scope for the directory change
---@param log boolean? Whether to log the change
---@return string # The final working directory
function Lpke_cd_root(scope, log)
  return Lpke_cd('', scope, log)
end
