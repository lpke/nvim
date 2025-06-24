local helpers = require('lpke.core.helpers')

local function format_registers(registers)
  if type(registers) ~= 'string' then
    if registers == true then
      return 'registers: "*+'
    else
      return 'register: "'
    end
  else
    local seen = {}
    local reg_list = {}
    for i = 1, #registers do
      local char = registers:sub(i, i)
      if not seen[char] then
        seen[char] = true
        table.insert(reg_list, char)
      end
    end
    return 'register'
      .. (#reg_list > 1 and 's: "' or ': "')
      .. table.concat(reg_list, '')
  end
end

-- yanks contents into desired register/s
function Lpke_yank(contents, registers)
  -- Always yank to the default register
  vim.fn.setreg('"', contents)

  if type(registers) == 'string' then
    for i = 1, #registers do
      local reg = registers:sub(i, i)
      vim.fn.setreg(reg, contents)
    end
  elseif registers == true then
    vim.fn.setreg('*', contents)
    vim.fn.setreg('+', contents)
  end
  -- If registers == false, we only yank to the default register (already done above)

  return contents
end

-- yank current buf name (path) to specified register (used for user command: `YP`/`Yp`)
function Lpke_yank_buf_name(cmd, global)
  local buf_name = helpers.get_buf_name(0, true)
  local registers_used
  if cmd.args and (cmd.args ~= '') then
    registers_used = cmd.args
    Lpke_yank(buf_name, cmd.args)
  else
    registers_used = global
    Lpke_yank(buf_name, global)
  end

  local message = 'Yanked buffer name ('
    .. format_registers(registers_used)
    .. '): '
    .. buf_name
  vim.notify(message, vim.log.levels.INFO)
end

-- yank current location (file:line) to specified register (optionally with blame info)
function Lpke_yank_location(cmd, global)
  local current_file = vim.fn.expand('%:p')
  if not current_file or current_file == '' then
    vim.notify('No file to yank location from', vim.log.levels.WARN)
    return
  end

  local current_line = vim.fn.line('.')
  local relative_path = vim.fn.fnamemodify(current_file, ':~:.')
  local location = relative_path .. ':' .. current_line

  -- Check if blame info is requested (look for 'blame' in cmd args)
  local with_blame = cmd and cmd.args and string.find(cmd.args, 'blame')

  -- Add blame info if requested
  if with_blame then
    local blame_info = vim.fn.system(
      'git blame -L '
        .. current_line
        .. ','
        .. current_line
        .. ' --porcelain '
        .. current_file
    )

    if vim.v.shell_error ~= 0 then
      vim.notify(
        'Failed to get git blame: ' .. blame_info,
        vim.log.levels.ERROR
      )
      return
    end

    -- Parse porcelain format to extract author and time
    local author = blame_info:match('author ([^\n]+)')
    local author_time = blame_info:match('author%-time (%d+)')

    if not author or not author_time then
      vim.notify('Failed to parse git blame info', vim.log.levels.ERROR)
      return
    end

    -- Convert timestamp to readable format
    local formatted_time = os.date('%Y-%m-%d %H:%M', tonumber(author_time))
    location = location .. ' - ' .. author .. ' @ ' .. formatted_time
  end

  -- Handle register specification similar to Lpke_yank_buf_name
  local registers_used
  if cmd and cmd.args and (cmd.args ~= '') then
    -- Extract register part (remove 'blame' if present)
    local register_arg = cmd.args
      :gsub('blame%s*', '')
      :gsub('%s*blame', '')
      :gsub('^%s+', '')
      :gsub('%s+$', '')
    if register_arg ~= '' then
      registers_used = register_arg
      Lpke_yank(location, register_arg)
    else
      registers_used = global
      Lpke_yank(location, global)
    end
  else
    registers_used = global
    Lpke_yank(location, global)
  end

  local message = (
    with_blame and 'Yanked location with blame' or 'Yanked location'
  )
    .. ' ('
    .. format_registers(registers_used)
    .. '): '
    .. location
  vim.notify(message, vim.log.levels.INFO)
end

-- yank current tab id to specified register
function Lpke_yank_tab_id(cmd, global)
  local tab_id = tostring(vim.api.nvim_get_current_tabpage())
  local registers_used
  if cmd.args and (cmd.args ~= '') then
    registers_used = cmd.args
    Lpke_yank(tab_id, cmd.args)
  else
    registers_used = global
    Lpke_yank(tab_id, global)
  end

  local message = 'Yanked tab ID ('
    .. format_registers(registers_used)
    .. '): '
    .. tab_id
  vim.notify(message, vim.log.levels.INFO)
end

-- yank current buffer id to specified register
function Lpke_yank_buf_id(cmd, global)
  local buf_id = tostring(vim.api.nvim_get_current_buf())
  local registers_used
  if cmd.args and (cmd.args ~= '') then
    registers_used = cmd.args
    Lpke_yank(buf_id, cmd.args)
  else
    registers_used = global
    Lpke_yank(buf_id, global)
  end

  local message = 'Yanked buffer ID ('
    .. format_registers(registers_used)
    .. '): '
    .. buf_id
  vim.notify(message, vim.log.levels.INFO)
end

-- yank current window id to specified register
function Lpke_yank_win_id(cmd, global)
  local win_id = tostring(vim.api.nvim_get_current_win())
  local registers_used
  if cmd.args and (cmd.args ~= '') then
    registers_used = cmd.args
    Lpke_yank(win_id, cmd.args)
  else
    registers_used = global
    Lpke_yank(win_id, global)
  end

  local message = 'Yanked window ID ('
    .. format_registers(registers_used)
    .. '): '
    .. win_id
  vim.notify(message, vim.log.levels.INFO)
end

-- yank current working directory to specified register
function Lpke_yank_cwd(cmd, global)
  local cwd = vim.fn.getcwd()
  local registers_used
  if cmd.args and (cmd.args ~= '') then
    registers_used = cmd.args
    Lpke_yank(cwd, cmd.args)
  else
    registers_used = global
    Lpke_yank(cwd, global)
  end

  local message = 'Yanked current working directory ('
    .. format_registers(registers_used)
    .. '): '
    .. cwd
  vim.notify(message, vim.log.levels.INFO)
end

-- yank git root directory to specified register
function Lpke_yank_git_root(cmd, global)
  local git_root = Lpke_find_git_root()
  if not git_root then
    vim.notify('No git repository found', vim.log.levels.WARN)
    return
  end

  local registers_used
  if cmd.args and (cmd.args ~= '') then
    registers_used = cmd.args
    Lpke_yank(git_root, cmd.args)
  else
    registers_used = global
    Lpke_yank(git_root, global)
  end

  local message = 'Yanked git root ('
    .. format_registers(registers_used)
    .. '): '
    .. git_root
  vim.notify(message, vim.log.levels.INFO)
end
