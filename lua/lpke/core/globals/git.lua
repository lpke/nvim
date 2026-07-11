-- find the git root of any path, or current file (if applicable)
function Lpke_find_git_root(path)
  -- Handle nil or empty path - use current buffer's path
  if not path or path == '' then
    path = vim.api.nvim_buf_get_name(0)
    if vim.bo.filetype == 'oil' then
      path = path:gsub('^oil://', '')
    end
    if path == '' then
      return nil -- Current buffer has no file
    end
  end

  -- Convert to absolute path and get directory
  local current_path = vim.fn.fnamemodify(path, ':p')
  if vim.fn.isdirectory(current_path) == 0 then
    current_path = vim.fn.fnamemodify(current_path, ':h')
  end

  -- Traverse up the directory tree
  while current_path and current_path ~= '/' do
    local git_dir = current_path .. '/.git'
    -- check if .git is a directory (most cases)
    if vim.fn.isdirectory(git_dir) == 1 then
      return current_path
    -- check if .git is a file (worktrees)
    elseif vim.fn.filereadable(git_dir) == 1 then
      local git_file_content = vim.fn.readfile(git_dir)[1]
      if git_file_content and git_file_content:match('^gitdir: ') then
        return current_path
      end
    end

    -- Move to parent directory
    local parent = vim.fn.fnamemodify(current_path, ':h')
    if parent == current_path then
      break -- Reached filesystem root
    end
    current_path = parent
  end

  return nil
end

-- print the git root
function Lpke_git_root(path)
  print(Lpke_find_git_root(path))
end

-- run the zsh `gpp` helper with raw :Gpp args
function Lpke_gpp(cmd)
  local args = cmd and cmd.args or ''
  local helper = vim.fn.expand('~/.config/zsh/helpers/10_git-any.zsh')

  if vim.fn.filereadable(helper) ~= 1 then
    vim.notify(
      'Gpp: zsh helper not found. Tried: ' .. helper,
      vim.log.levels.ERROR
    )
    return
  end

  local shell_cmd = 'source ' .. vim.fn.shellescape(helper) .. '; gpp'
  if args ~= '' then
    shell_cmd = shell_cmd .. ' ' .. args
  end

  local function echo_result(output, code)
    output = vim.trim(output or '')
    local ok = code == 0

    if output == '' then
      output = ok and 'Gpp: done' or ('Gpp: exited with code ' .. code)
    end

    vim.schedule(function()
      vim.notify(output, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
    end)
  end

  vim.notify('Gpp: running', vim.log.levels.INFO)

  if vim.system then
    vim.system(
      { 'zsh', '-c', shell_cmd },
      { cwd = vim.fn.getcwd(), text = true },
      function(result)
        echo_result(
          table.concat({ result.stdout or '', result.stderr or '' }, ''),
          result.code
        )
      end
    )
    return
  end

  local output = {}
  local job_id = vim.fn.jobstart({ 'zsh', '-c', shell_cmd }, {
    cwd = vim.fn.getcwd(),
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      vim.list_extend(output, data)
    end,
    on_stderr = function(_, data)
      vim.list_extend(output, data)
    end,
    on_exit = function(_, code)
      echo_result(table.concat(output, '\n'), code)
    end,
  })
  if job_id <= 0 then
    vim.notify('Gpp: failed to start `gpp`', vim.log.levels.ERROR)
  end
end

-- run the interactive zsh `gitsquash` helper in a floating terminal
function Lpke_gsquash()
  Lpke_term(nil, {
    command = { 'zsh', '-ic', 'gitsquash' },
    close_on_exit = true,
    title = ' Git Squash ',
  })
end

-- open a new tab with 2 left/right windows, each with a seperate new buffer that has bufhidden=wipe and nomodified and buftype=nofile
function Lpke_diff()
  vim.cmd('tabnew')
  vim.bo.bufhidden = 'wipe'
  vim.bo.modified = false
  vim.bo.buftype = 'nofile'
  vim.api.nvim_buf_set_name(0, 'Temp File 2')

  vim.cmd('vsplit')
  vim.cmd('enew')
  vim.bo.bufhidden = 'wipe'
  vim.bo.modified = false
  vim.bo.buftype = 'nofile'
  vim.api.nvim_buf_set_name(0, 'Temp File 1')

  vim.cmd('windo diffthis')
  vim.cmd('wincmd H')

  vim.schedule(function()
    vim.cmd('windo set wrap')
    vim.cmd('wincmd h')
  end)
end
