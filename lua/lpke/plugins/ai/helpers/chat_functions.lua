local M = {}

local model_swap = require('lpke.plugins.ai.helpers.model_swap')

local DEFAULT_HTTP_TOOL_LINES = {
  '@{agent} @{fetch_webpage} @{web_search}',
}

local EMPTY_CHAT_TRAILING_BLANKS = 2

local DEFAULT_HTTP_TOOL_LINE_SET = {}
for _, line in ipairs(DEFAULT_HTTP_TOOL_LINES) do
  DEFAULT_HTTP_TOOL_LINE_SET[line] = true
end

local function put_text(text)
  vim.api.nvim_put({ text }, 'c', vim.fn.mode() == 'n', true)
end

local function is_http_tool_line(line)
  return DEFAULT_HTTP_TOOL_LINE_SET[line] == true
end

local function should_keep_blank_before_insert(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ''
  local prev_line = row > 1
      and vim.api.nvim_buf_get_lines(bufnr, row - 2, row - 1, false)[1]
    or ''

  return line == '' and prev_line:match('^## ') ~= nil
end

local function is_empty_chat_lines(lines, ignore_line)
  for _, line in ipairs(lines) do
    if
      line ~= ''
      and not line:match('^## ')
      and not line:match('^> ')
      and not (ignore_line and ignore_line(line))
    then
      return false
    end
  end
  return true
end

local function normalize_empty_chat_padding(lines)
  if not is_empty_chat_lines(lines) then
    return lines
  end

  while #lines > 0 and lines[#lines] == '' do
    table.remove(lines)
  end

  for _ = 1, EMPTY_CHAT_TRAILING_BLANKS do
    table.insert(lines, '')
  end
  return lines
end

-- Insert HTTP-only CodeCompanion tool variables at the current cursor position.
-- ACP adapters expose their own tools, so these prompt variables are noise there.
function M.insert_http_tools()
  if not model_swap.is_http_chat(0) then
    return false
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]

  if should_keep_blank_before_insert(bufnr, row) then
    vim.api.nvim_buf_set_lines(
      bufnr,
      row,
      row,
      false,
      vim.deepcopy(DEFAULT_HTTP_TOOL_LINES)
    )
    vim.api.nvim_win_set_cursor(0, { row + #DEFAULT_HTTP_TOOL_LINES, 0 })
    return true
  end

  for i, line in ipairs(DEFAULT_HTTP_TOOL_LINES) do
    if i == 1 then
      vim.cmd('normal! i' .. line)
    else
      vim.cmd('normal! o' .. line)
    end
  end
  return true
end

function M.insert_http_tool_text(text)
  if not model_swap.is_http_chat(0) then
    return false
  end

  put_text(text)
  return true
end

function M.insert_context_text(text)
  put_text(text)
end

function M.has_http_tool_context(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    if is_http_tool_line(line) then
      return true
    end
  end
  return false
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
  return is_empty_chat_lines(lines)
end

function M.is_chat_only_http_tool_context(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return M.has_http_tool_context(bufnr)
    and is_empty_chat_lines(lines, is_http_tool_line)
end

function M.remove_http_tool_context(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local filtered = vim.tbl_filter(function(line)
    return not is_http_tool_line(line)
  end, lines)

  if #filtered ~= #lines then
    filtered = normalize_empty_chat_padding(filtered)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, filtered)
    if vim.api.nvim_get_current_buf() == bufnr then
      vim.api.nvim_win_set_cursor(0, { #filtered, 0 })
    end
    return true
  end

  return false
end

function M.add_http_tool_context(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if not M.is_empty_chat(bufnr) or M.has_http_tool_context(bufnr) then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local insert_at = #lines
  while insert_at > 0 and lines[insert_at] == '' do
    insert_at = insert_at - 1
  end

  local inserted_lines =
    vim.list_extend({ '' }, vim.deepcopy(DEFAULT_HTTP_TOOL_LINES))
  vim.list_extend(inserted_lines, { '', '' })
  vim.api.nvim_buf_set_lines(bufnr, insert_at, #lines, false, inserted_lines)

  if vim.api.nvim_get_current_buf() == bufnr then
    vim.api.nvim_win_set_cursor(0, { insert_at + #inserted_lines, 0 })
  end

  return true
end

function M.sync_http_tools_for_adapter_change(bufnr, from_adapter, to_adapter)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  if
    model_swap.is_http_adapter(from_adapter)
    and model_swap.is_acp_adapter(to_adapter)
    and M.is_chat_only_http_tool_context(bufnr)
  then
    return M.remove_http_tool_context(bufnr)
  end

  if
    model_swap.is_acp_adapter(from_adapter)
    and model_swap.is_http_adapter(to_adapter)
    and M.is_empty_chat(bufnr)
  then
    return M.add_http_tool_context(bufnr)
  end

  return false
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

-- Toggle chat, insert HTTP tools only if it's a fresh/empty HTTP chat.
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
    if M.insert_http_tools() then
      vim.cmd('normal! G2o')
    end
  end
  vim.cmd('stopinsert')
end

-- Always open a new chat, adding HTTP tools only for HTTP adapters.
function M.open_new_chat_with_tools(opts)
  opts = opts or {}
  if not opts.from_chat_keymap and M.toggle_if_already_in_chat() then
    return
  end
  vim.cmd('CodeCompanionChat')
  if M.insert_http_tools() then
    vim.cmd('normal! G2o')
  end
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
  local inserted_tools = M.insert_http_tools()
  if selection ~= '' then
    vim.cmd(inserted_tools and 'normal! 2o' or 'normal! Go')
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
    if is_fresh and M.insert_http_tools() then
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
