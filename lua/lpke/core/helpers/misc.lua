---@class lpke.core.helpers.misc
local M = {}

local util = require('lpke.core.helpers.util')

-- pastes from register with unix line endings
function M.paste_unix(register, above)
  local content = vim.fn.getreg(register)
  local fixed_content = vim.fn.substitute(content, '\r\n', '\n', 'g')
  fixed_content = fixed_content:gsub('\n$', '')
  vim.fn.setreg(register, fixed_content)
  vim.cmd('normal! "' .. register .. (above and 'P' or 'p'))
end

-- toggle 'list' option (show whitespace chars)
function M.toggle_show_whitespace()
  local is_list = vim.wo.list
  vim.wo.list = not is_list
end

-- stop currently focused terminal
function M.stop_term()
  vim.fn.jobstop(vim.b.terminal_job_id)
  vim.cmd('sleep 100m')
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<Esc>', true, true, true),
    'n',
    false
  )
end

-- execute a string as Lua code
function M.execute_as_lua(code_string)
  local func, err = load('return ' .. code_string)
  if func then
    return func()
  else
    vim.notify(err or 'unknown error', vim.log.levels.ERROR)
  end
end

-- quickfix navigation: direction = 1 (next), -1 (prev)
function M.qf_nav(direction)
  util.safe_call(function()
    local qf = vim.fn.getqflist({ idx = 0 })
    local qf_size = #vim.fn.getqflist()
    local qf_idx = qf.idx
    if qf_size == 1 then
      vim.cmd('cfirst')
      return
    end
    if direction == 1 then
      if qf_idx == qf_size then
        vim.cmd('clast')
        if vim.fn.getqflist({ idx = 0 }).idx == qf_size then
          vim.notify('Already at last quickfix item', vim.log.levels.INFO)
        end
      else
        vim.cmd('cnext')
      end
    else
      if qf_idx == 1 then
        vim.cmd('cfirst')
        if vim.fn.getqflist({ idx = 0 }).idx == 1 then
          vim.notify('Already at first quickfix item', vim.log.levels.INFO)
        end
      else
        vim.cmd('cprev')
      end
    end
  end, true)
end

-- quickfix item deletion by line, maintaining cursor and selection position
function M.qf_del(start_line, end_line)
  local qf_list = vim.fn.getqflist()
  local current_idx = vim.fn.getqflist({ idx = 0 }).idx

  -- Remove items in reverse order to maintain correct indices
  for i = end_line, start_line, -1 do
    table.remove(qf_list, i)
  end
  vim.fn.setqflist(qf_list, 'r')

  -- Determine the new quickfix index to select
  local new_idx
  if current_idx < start_line then
    -- Current item was before the deleted range, keep same index
    new_idx = current_idx
  elseif current_idx > end_line then
    -- Current item was after the deleted range, adjust for deleted items
    new_idx = current_idx - (end_line - start_line + 1)
  else
    -- Current item was in the deleted range, select the item at start_line position
    new_idx = math.min(start_line, #qf_list)
  end

  -- Set the quickfix index and cursor position
  if new_idx > 0 and #qf_list > 0 then
    vim.fn.setqflist({}, 'a', { idx = new_idx })
    vim.fn.cursor(new_idx, 1)
  end
end

return M
