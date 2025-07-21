---@class lpke.core.helpers.print
local M = {}

-- prints a message 'over' the previous message
function M.print_over(msg, history, height)
  history = history or false
  local orig_height = vim.o.cmdheight
  vim.o.cmdheight = height or 2
  if history then
    print(msg)
  else
    vim.cmd('echo "' .. msg .. '"')
  end
  vim.o.cmdheight = orig_height
end

-- clear the latest message if it contains `target`
function M.clear_last_message(target)
  local messages = vim.fn.execute('messages')
  local lines = vim.split(messages, '\n')
  local last_line = lines[#lines]

  if string.find(last_line, target, 1, true) then
    M.print_over(' ')
  end
end

return M
