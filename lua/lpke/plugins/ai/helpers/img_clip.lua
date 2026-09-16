local M = {}

local MAX_DIR_SIZE_BYTES = 2 * 1024 * 1024 * 1024

local checked_size_this_session = false
local inline_paste_patched = false

function M.setup_inline_paste()
  if inline_paste_patched then
    return
  end

  local markup = require('img-clip.markup')
  local config = require('img-clip.config')
  local insert_markup = markup.insert_markup

  -- img-clip always inserts whole lines. Chat image links belong at the cursor.
  markup.insert_markup = function(input, is_file_path)
    if vim.bo.filetype ~= 'codecompanion' then
      return insert_markup(input, is_file_path)
    end

    local template = markup.get_template(input, is_file_path)
    if not template then
      return false
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local row, col = cursor[1] - 1, cursor[2]
    local lines = vim.split(template, '\n', { plain = true })
    vim.api.nvim_buf_set_text(0, row, col, row, col, lines)

    local end_row = row + #lines
    local end_col = #lines == 1 and col + #lines[1] or #lines[#lines]
    vim.api.nvim_win_set_cursor(0, { end_row, end_col })
    if config.get_opt('insert_mode_after_paste') then
      if end_col == #vim.api.nvim_get_current_line() then
        vim.cmd('startinsert!')
      else
        vim.cmd('startinsert')
      end
    end
    return true
  end

  inline_paste_patched = true
end

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
