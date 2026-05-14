local M = {}

local api = vim.api
local helpers = require('lpke.core.helpers')

M.config = {
  backup_dir = vim.fn.stdpath('data') .. '/no-name-backups',
  max_backups = 100,
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.WARN)
end

local function is_no_name_buf(bufnr)
  return bufnr
    and api.nvim_buf_is_valid(bufnr)
    and api.nvim_buf_is_loaded(bufnr)
    and api.nvim_buf_get_name(bufnr) == ''
    and vim.bo[bufnr].buftype == ''
end

local function has_content(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return #lines > 1 or lines[1] ~= ''
end

local function ensure_dir()
  vim.fn.mkdir(M.config.backup_dir, 'p')
end

local function epoch_ms()
  local sec, usec = (vim.uv or vim.loop).gettimeofday()
  return sec * 1000 + math.floor(usec / 1000)
end

local function sanitized_filetype(bufnr)
  local filetype = vim.trim(vim.bo[bufnr].filetype or '')
  filetype = filetype
    :gsub('%s+', '-')
    :gsub('[/%\\:]+', '-')
    :gsub('[^%w%._-]+', '-')
    :gsub('%-+', '-')
    :gsub('^%-', '')
    :gsub('%-$', '')

  return filetype ~= '' and filetype or 'no-filetype'
end

local function backup_files()
  ensure_dir()
  local files = vim.fn.glob(M.config.backup_dir .. '/*_no-name.*', false, true)

  table.sort(files, function(a, b)
    local a_epoch = tonumber(
      vim.fn.fnamemodify(a, ':t'):match('^(%d+)_no%-name%.')
    ) or 0
    local b_epoch = tonumber(
      vim.fn.fnamemodify(b, ':t'):match('^(%d+)_no%-name%.')
    ) or 0

    if a_epoch == b_epoch then
      return a < b
    end
    return a_epoch < b_epoch
  end)

  return files
end

local function collect_old_backups()
  local files = backup_files()
  local excess = #files - M.config.max_backups

  for i = 1, excess do
    pcall(vim.fn.delete, files[i])
  end
end

local function backup_path(bufnr)
  ensure_dir()

  local timestamp = epoch_ms()
  local filetype = sanitized_filetype(bufnr)
  local path =
    string.format('%s/%d_no-name.%s', M.config.backup_dir, timestamp, filetype)

  while vim.fn.filereadable(path) == 1 do
    timestamp = timestamp + 1
    path = string.format(
      '%s/%d_no-name.%s',
      M.config.backup_dir,
      timestamp,
      filetype
    )
  end

  return path
end

local function save_backup(bufnr)
  local path = backup_path(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local ok, result = pcall(vim.fn.writefile, lines, path, 'b')

  if not ok or result ~= 0 then
    notify(
      'Failed to back up [No Name] buffer: ' .. tostring(result),
      vim.log.levels.ERROR
    )
    return nil
  end

  collect_old_backups()
  return path
end

local function mark_clean(bufnr)
  pcall(api.nvim_set_option_value, 'modified', false, { buf = bufnr })
end

local function delete_if_hidden(bufnr)
  if
    api.nvim_buf_is_valid(bufnr)
    and is_no_name_buf(bufnr)
    and #vim.fn.win_findbuf(bufnr) == 0
  then
    pcall(api.nvim_buf_delete, bufnr, { force = true })
  end
end

function M.save_current()
  local bufnr = api.nvim_get_current_buf()
  if is_no_name_buf(bufnr) then
    notify(
      "Cannot save [No Name] buffer. Use ':w <path/filename>'",
      vim.log.levels.WARN
    )
    return
  end

  vim.cmd('w')
  pcall(function()
    require('lualine').refresh()
  end)
end

function M.close_current()
  local bufnr = api.nvim_get_current_buf()
  local handle_no_name = is_no_name_buf(bufnr)
    and #vim.fn.win_findbuf(bufnr) == 1
  local was_modified = handle_no_name and vim.bo[bufnr].modified
  local backup

  if handle_no_name and was_modified then
    if has_content(bufnr) then
      backup = save_backup(bufnr)
      if not backup then
        return
      end
    end
    mark_clean(bufnr)
  end

  Lpke_close_win()

  if handle_no_name then
    delete_if_hidden(bufnr)

    if backup and not api.nvim_buf_is_valid(bufnr) then
      notify(
        "Killed [No Name] buffer. Restore with ':NNRestore'. Backup saved to: "
          .. backup,
        vim.log.levels.WARN
      )
    elseif was_modified and api.nvim_buf_is_valid(bufnr) then
      pcall(api.nvim_set_option_value, 'modified', true, { buf = bufnr })
    end
  end
end

function M.restore(count_arg)
  local count = tonumber(count_arg) or 1
  if count < 1 then
    notify('NNRestore count must be greater than 0', vim.log.levels.WARN)
    return
  end

  local files = backup_files()
  if #files == 0 then
    notify('No [No Name] backups found', vim.log.levels.WARN)
    return
  end

  for i = #files, math.max(#files - count + 1, 1), -1 do
    vim.cmd('tabnew ' .. vim.fn.fnameescape(files[i]))
  end
end

helpers.command_set_multi({
  {
    '?',
    'NNRestore',
    function(cmd)
      M.restore(cmd.fargs[1])
    end,
    { desc = 'Restore [No Name] buffer backups' },
  },
  {
    '?',
    'NN',
    function(cmd)
      M.restore(cmd.fargs[1])
    end,
    { desc = 'Restore [No Name] buffer backups' },
  },
})

return M
