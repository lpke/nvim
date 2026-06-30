local M = {}

local MAX_DIR_SIZE_BYTES = 2 * 1024 * 1024 * 1024

local checked_size_this_session = false

function M.dir_path()
  return vim.fn.stdpath('data') .. '/img-clip-pasted-images'
end

local function notify_if_over_limit(bytes, dir)
  if bytes <= MAX_DIR_SIZE_BYTES then
    return
  end

  local gib = bytes / (1024 * 1024 * 1024)
  vim.notify(
    string.format(
      'Pasted image directory is %.2f GB, over the 2 GB warning limit:\n%s',
      gib,
      dir
    ),
    vim.log.levels.WARN,
    { title = 'img-clip.nvim' }
  )
end

local function handle_dir_size(stdout, dir, exit_code)
  if exit_code ~= 0 then
    return
  end

  local bytes = tonumber((stdout or ''):match('^%s*(%d+)'))
  if not bytes then
    return
  end

  vim.schedule(function()
    notify_if_over_limit(bytes, dir)
  end)
end

local function check_dir_size_once()
  if checked_size_this_session then
    return
  end
  checked_size_this_session = true

  if vim.fn.executable('du') ~= 1 then
    return
  end

  local dir = M.dir_path()
  if vim.fn.isdirectory(dir) ~= 1 then
    return
  end

  if vim.system then
    vim.system({ 'du', '-sb', dir }, { text = true }, function(result)
      handle_dir_size(result.stdout, dir, result.code)
    end)
    return
  end

  local output = {}
  vim.fn.jobstart({ 'du', '-sb', dir }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      vim.list_extend(
        output,
        vim.tbl_filter(function(line)
          return line ~= ''
        end, data)
      )
    end,
    on_exit = function(_, exit_code)
      handle_dir_size(table.concat(output, '\n'), dir, exit_code)
    end,
  })
end

function M.paste_image()
  local ok, img_clip = pcall(require, 'img-clip')
  if not ok then
    vim.notify('img-clip.nvim is not available', vim.log.levels.ERROR, {
      title = 'img-clip.nvim',
    })
    return
  end

  local pasted = img_clip.paste_image()
  if pasted then
    check_dir_size_once()
  end
end

return M
