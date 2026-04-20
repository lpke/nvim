local M = {}

local DEFAULT_CONTEXT_LINES = {
  '@{agent} @{fetch_webpage} @{web_search}',
}

-- Insert the default context tools at the current cursor position.
function M.insert_default_context()
  for i, line in ipairs(DEFAULT_CONTEXT_LINES) do
    if i == 1 then
      vim.cmd('normal! i' .. line)
    else
      vim.cmd('normal! o' .. line)
    end
  end
end

-- Build a code block from a selection string, trimming any trailing blank line.
function M.build_code_block(selection, filetype)
  local lines = vim.split(selection, '\n')
  -- Remove trailing empty element from a newline-terminated selection
  if #lines > 0 and lines[#lines] == '' then
    table.remove(lines)
  end
  local block = { '```' .. filetype }
  vim.list_extend(block, lines)
  vim.list_extend(block, { '```' })
  return block
end

function M.toggle_if_already_in_chat()
  if vim.bo.filetype == 'codecompanion' then
    vim.cmd('CodeCompanionChat Toggle')
    return true
  end
  return false
end

-- Check if a chat buffer is empty/untouched (only has the initial header,
-- optionally with auto-injected context like AGENTS.md rules)
function M.is_empty_chat(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    if line ~= '' and not line:match('^## ') and not line:match('^> ') then
      return false
    end
  end
  return true
end

-- Close any codecompanion windows in other tabs
function M.close_cc_in_other_tabs()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab ~= vim.api.nvim_get_current_tabpage() then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if
          vim.api.nvim_get_option_value('filetype', { buf = buf })
          == 'codecompanion'
        then
          vim.api.nvim_win_close(win, false)
          break
        end
      end
    end
  end
end


-- Toggle chat, insert default context only if it's a fresh/empty chat
function M.toggle_cc_with_default_tools()
  if M.toggle_if_already_in_chat() then
    return
  end
  M.close_cc_in_other_tabs()
  vim.cmd('CodeCompanionChat Toggle')
  if
    vim.bo.filetype == 'codecompanion'
    and M.is_empty_chat(vim.api.nvim_get_current_buf())
  then
    vim.cmd('normal! G')
    M.insert_default_context()
    vim.cmd('normal! G2o')
  end
  vim.cmd('stopinsert')
end

-- Always open a new chat with default context
function M.open_new_chat_with_tools()
  if M.toggle_if_already_in_chat() then
    return
  end
  vim.cmd('CodeCompanionChat')
  M.insert_default_context()
  vim.cmd('normal! G2o')
  vim.cmd('stopinsert')
end

function M.open_new_chat_with_context_selection()
  if M.toggle_if_already_in_chat() then
    return
  end
  -- copy selection before opening the chat
  vim.cmd('normal! "vy')
  local selection = vim.fn.getreg('v')
  local filetype = vim.bo.filetype
  vim.cmd('CodeCompanionChat')
  M.insert_default_context()
  if selection ~= '' then
    vim.cmd('normal! 2o')
    vim.api.nvim_put(M.build_code_block(selection, filetype), 'l', true, true)
    vim.cmd('normal! 2o')
  end
  vim.cmd('stopinsert')
end

function M.toggle_chat_with_context_selection()
  if M.toggle_if_already_in_chat() then
    return
  end
  -- copy selection
  vim.cmd('normal! "vy')
  local selection = vim.fn.getreg('v')
  local filetype = vim.bo.filetype
  -- check for codecompanion windows in current tab
  local cc_win = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if
      vim.api.nvim_buf_is_loaded(buf)
      and vim.api.nvim_get_option_value('filetype', { buf = buf })
        == 'codecompanion'
    then
      cc_win = win
      break
    end
  end
  -- if codecompanion window is already open in current tab, focus it
  if cc_win then
    vim.api.nvim_set_current_win(cc_win)
  else
    vim.cmd('CodeCompanionChat Toggle')
  end
  -- insert selection in a code block
  if selection ~= '' then
    local is_fresh = M.is_empty_chat(vim.api.nvim_get_current_buf())
    if is_fresh then
      M.insert_default_context()
      vim.cmd('normal! 2o')
    else
      vim.cmd('normal! Go')
    end
    vim.api.nvim_put(M.build_code_block(selection, filetype), 'l', true, true)
    vim.cmd('normal! 2o')
    vim.cmd('stopinsert')
  end
end

function M.open_inline_prompt_with_context()
  if vim.bo.filetype == 'codecompanion' then
    return
  end
  vim.cmd('CodeCompanion')
  vim.api.nvim_input('#{buffer} ')
end

return M

