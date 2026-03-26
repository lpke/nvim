local M = {}

function M.toggle_if_already_in_chat()
  if vim.bo.filetype == 'codecompanion' then
    vim.cmd('CodeCompanionChat Toggle')
    return true
  end
  return false
end

-- toggle the codecompanion chat buffer
function Lpke_toggle_cc()
  -- stylua: ignore
  if M.toggle_if_already_in_chat() then return end
  -- find and close any codecompanion windows in other tabs
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
  -- toggle codecompanion chat normally
  vim.cmd('CodeCompanionChat Toggle')
  vim.cmd('stopinsert')
end

function M.open_new_chat_with_context()
  if M.toggle_if_already_in_chat() then
    return
  end
  vim.cmd('CodeCompanionChat')
  vim.cmd('normal! i#{buffer}')
  vim.cmd('normal! o#{diagnostics}')
  vim.cmd('normal! o')
  vim.cmd('normal! o@{agent}')
  vim.cmd('normal! o@{fetch_webpage}')
  vim.cmd('normal! o@{web_search}')
  vim.cmd('normal! G2o')
  vim.cmd('stopinsert')
end

function M.open_new_chat_with_context_selection()
  if M.toggle_if_already_in_chat() then
    return
  end
  vim.cmd('CodeCompanionChat')
  vim.cmd('normal! gg}}{i#{buffer}')
  vim.cmd('normal! o#{diagnostics}')
  vim.cmd('normal! o')
  vim.cmd('normal! o@{agent}')
  vim.cmd('normal! o@{fetch_webpage}')
  vim.cmd('normal! o@{web_search}')
  vim.cmd('normal! o')
  vim.cmd('normal! G2o')
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
    -- toggle chat if no codecompanion window exists in current tab
    vim.cmd('CodeCompanionChat Toggle')
  end
  -- insert selection in a code block
  if selection ~= '' then
    vim.cmd('normal! o#{buffer}')
    vim.cmd('normal! o#{diagnostics}')
    vim.cmd('normal! o')
    vim.cmd('normal! o@{agent}')
    vim.cmd('normal! o@{fetch_webpage}')
    vim.cmd('normal! o@{web_search}')
    vim.cmd('normal! o')
    local code_block_lines = { '```' .. filetype }
    vim.list_extend(code_block_lines, vim.split(selection, '\n'))
    vim.list_extend(code_block_lines, { '```' })
    vim.api.nvim_put(code_block_lines, 'l', true, true)
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
