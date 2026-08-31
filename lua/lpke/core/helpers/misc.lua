---@class lpke.core.helpers.misc
local M = {}

local util = require('lpke.core.helpers.util')

local mac_clipboard_host = 'mbp'

local function notify_mac_clipboard_error(action, result)
  local message = vim.trim(result.stderr or '')
  if message == '' then
    message = 'exit code ' .. result.code
  end
  vim.notify(
    'Mac clipboard ' .. action .. ' failed: ' .. message,
    vim.log.levels.ERROR
  )
end

-- sends the global clipboard register to the Mac clipboard over SSH
function M.copy_global_clipboard_to_mac()
  vim.system(
    { 'ssh', mac_clipboard_host, 'pbcopy' },
    { stdin = vim.fn.getreg('+'), text = true },
    function(result)
      if result.code ~= 0 then
        vim.schedule(function()
          notify_mac_clipboard_error('copy', result)
        end)
      end
    end
  )
end

-- arms a global yank expression to copy to the Mac after the yank completes
function M.yank_to_mac(keys)
  local yank_autocmd
  local mode_autocmd = vim.api.nvim_create_autocmd('ModeChanged', {
    pattern = 'no*:n',
    once = true,
    callback = function()
      pcall(vim.api.nvim_del_autocmd, yank_autocmd)
    end,
  })

  yank_autocmd = vim.api.nvim_create_autocmd('TextYankPost', {
    once = true,
    callback = function()
      pcall(vim.api.nvim_del_autocmd, mode_autocmd)
      if vim.v.event.operator == 'y' and vim.v.event.regname == '+' then
        M.copy_global_clipboard_to_mac()
      end
    end,
  })

  return keys
end

-- fetches the Mac clipboard over SSH, updates +, then pastes it
function M.paste_from_mac(above)
  local result = vim
    .system({ 'ssh', mac_clipboard_host, 'pbpaste' }, { text = true })
    :wait()
  if result.code ~= 0 then
    notify_mac_clipboard_error('paste', result)
    return
  end

  vim.fn.setreg('+', result.stdout or '', 'v')
  vim.cmd('normal! "+' .. (above and 'P' or 'p'))
end

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
  Lpke_feedkeys('<Esc>', 'n')
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
    if qf_size == 0 then
      vim.notify('No items in quickfix list', vim.log.levels.INFO)
      return
    end
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
