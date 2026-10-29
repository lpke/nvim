local M = {}
local helpers = require('lpke.core.helpers.info')
local last_source_bufnr
local source_tracker_started = false

local function is_codecompanion_buf(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local filetype = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  return filetype == 'codecompanion' or filetype == 'codecompanion_input'
end

local function is_oil_buf(bufnr)
  return helpers.get_oil_buf_type(bufnr) == 'oil'
end

local function track_source_buf(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if is_codecompanion_buf(bufnr) then
    return
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return
  end

  last_source_bufnr = bufnr
end

local function source_path_for_buf(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  if is_oil_buf(bufnr) then
    local ok, oil = pcall(require, 'oil')
    if not ok then
      return nil
    end

    local dir = oil.get_current_dir(bufnr)
    if dir and dir ~= '' then
      return vim.fn.fnamemodify(dir, ':p')
    end
    return nil
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name ~= '' then
    return vim.fn.fnamemodify(name, ':p')
  end
end

local function source_path()
  if
    last_source_bufnr
    and vim.api.nvim_buf_is_valid(last_source_bufnr)
    and not is_codecompanion_buf(last_source_bufnr)
  then
    local path = source_path_for_buf(last_source_bufnr)
    if path then
      return path
    end
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if not is_codecompanion_buf(bufnr) then
      local path = source_path_for_buf(bufnr)
      if path then
        return path
      end
    end
  end
end

local function escaped_path_text(path)
  return '`' .. path:gsub('`', '\\`') .. '`'
end

local function insert_text_at_cursor(text)
  local bufnr = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local col = math.min(cursor[2], #line)

  vim.api.nvim_buf_set_text(bufnr, row, col, row, col, { text })
  vim.api.nvim_win_set_cursor(0, { cursor[1], col + #text })
end

function M.setup()
  if source_tracker_started then
    return
  end
  source_tracker_started = true

  vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
    group = vim.api.nvim_create_augroup('LpkeCodeCompanionSourcePath', {
      clear = true,
    }),
    callback = function(args)
      track_source_buf(args.buf)
    end,
  })

  track_source_buf(vim.api.nvim_get_current_buf())
end

function M.insert()
  M.setup()

  local path = source_path()
  if not path then
    vim.notify(
      'No source buffer path available',
      vim.log.levels.INFO,
      { title = 'CodeCompanion' }
    )
    return
  end

  insert_text_at_cursor(escaped_path_text(path))
end

return M
