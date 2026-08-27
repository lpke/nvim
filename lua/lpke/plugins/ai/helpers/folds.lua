local M = {}

local RECENT_LINE_COUNT = 300
local MIN_HIDDEN_LINE_COUNT = 300
local enabled_chat_buffers = {}
local long_chat_folds = {}

local function default_fold_text()
  local ok, text = pcall(vim.fn.foldtext)
  if ok and type(text) == 'string' and text ~= '' then
    return text
  end

  local line = vim.fn.getline(vim.v.foldstart)
  return line ~= '' and line or ''
end

local function chat_role_headers(chat)
  if not chat.ui or not chat.ui.roles then
    return {}
  end

  local headers = {}
  for _, role in pairs(chat.ui.roles) do
    local ok, header = pcall(chat.ui.format_header, chat.ui, role)
    if ok then
      headers[header] = true
    end
  end
  return headers
end

local function long_chat_fold_end(chat, line_count)
  local target = line_count - RECENT_LINE_COUNT
  local headers = chat_role_headers(chat)
  local lines = vim.api.nvim_buf_get_lines(chat.bufnr, 0, target, false)

  for line = #lines, MIN_HIDDEN_LINE_COUNT + 1, -1 do
    if headers[lines[line]] then
      return line - 1
    end
  end
end

local function notify(message)
  vim.notify(message, vim.log.levels.INFO, { title = 'CodeCompanion' })
end

local function replace_long_chat_fold(chat, winnr, end_line)
  if
    not vim.api.nvim_win_is_valid(winnr)
    or vim.api.nvim_win_get_buf(winnr) ~= chat.bufnr
  then
    long_chat_folds[winnr] = nil
    return false
  end

  local ok, err = pcall(vim.api.nvim_win_call, winnr, function()
    local view = vim.fn.winsaveview()
    local state = long_chat_folds[winnr]

    local owns_start_fold = state and state.bufnr == chat.bufnr
    if
      (owns_start_fold or enabled_chat_buffers[chat.bufnr])
      and vim.fn.foldlevel(1) > 0
    then
      if vim.fn.foldclosed(1) == 1 then
        vim.cmd('1foldopen')
      end
      vim.fn.cursor(1, 1)
      vim.cmd('normal! zd')
    end

    long_chat_folds[winnr] = nil
    if end_line then
      vim.wo.foldenable = true
      vim.wo.foldmethod = 'manual'
      long_chat_folds[winnr] = {
        bufnr = chat.bufnr,
        end_line = end_line,
      }
      vim.cmd(('1,%dfold'):format(end_line))
      vim.cmd('1foldclose')
    end

    vim.fn.winrestview(view)
  end)

  if not ok then
    long_chat_folds[winnr] = nil
    vim.notify(err, vim.log.levels.ERROR, { title = 'CodeCompanion' })
    return false
  end

  return true
end

local function long_chat_windows(bufnr)
  local windows = {}
  local seen = {}
  for winnr, state in pairs(long_chat_folds) do
    if state.bufnr == bufnr then
      table.insert(windows, winnr)
      seen[winnr] = true
    end
  end
  for _, winnr in ipairs(vim.fn.win_findbuf(bufnr)) do
    if not seen[winnr] then
      table.insert(windows, winnr)
    end
  end
  return windows
end

local function refresh_long_chat_folds(chat)
  local line_count = vim.api.nvim_buf_line_count(chat.bufnr)
  if line_count <= RECENT_LINE_COUNT + MIN_HIDDEN_LINE_COUNT then
    for _, winnr in ipairs(long_chat_windows(chat.bufnr)) do
      replace_long_chat_fold(chat, winnr)
    end
    enabled_chat_buffers[chat.bufnr] = nil
    return
  end

  local end_line = long_chat_fold_end(chat, line_count)
  if not end_line then
    for _, winnr in ipairs(long_chat_windows(chat.bufnr)) do
      replace_long_chat_fold(chat, winnr)
    end
    enabled_chat_buffers[chat.bufnr] = nil
    return
  end

  local refreshed = false
  for _, winnr in ipairs(vim.fn.win_findbuf(chat.bufnr)) do
    refreshed = replace_long_chat_fold(chat, winnr, end_line) or refreshed
  end
  if not refreshed and not vim.tbl_isempty(vim.fn.win_findbuf(chat.bufnr)) then
    enabled_chat_buffers[chat.bufnr] = nil
    return
  end
  return end_line
end

local function show_full_chat(chat)
  for _, winnr in ipairs(vim.fn.win_findbuf(chat.bufnr)) do
    vim.api.nvim_win_call(winnr, function()
      if vim.fn.foldclosed(1) == 1 then
        vim.cmd('1foldopen')
      end
    end)
  end
end

local function setup_long_chat_autocmds()
  local group = vim.api.nvim_create_augroup('LpkeCodeCompanionLongChatFolds', {
    clear = true,
  })

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = {
      'CodeCompanionChatSubmitted',
      'CodeCompanionChatDone',
      'CodeCompanionChatStopped',
      'CodeCompanionChatOpened',
      'CodeCompanionChatRestored',
    },
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if not bufnr or not enabled_chat_buffers[bufnr] then
        return
      end

      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        local chat = require('codecompanion').buf_get_chat(bufnr)
        if chat then
          refresh_long_chat_folds(chat)
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    callback = function(args)
      if not enabled_chat_buffers[args.buf] then
        return
      end

      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(args.buf) then
          return
        end
        local chat = require('codecompanion').buf_get_chat(args.buf)
        if chat then
          refresh_long_chat_folds(chat)
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = { 'CodeCompanionChatCleared', 'CodeCompanionChatClosed' },
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if not bufnr then
        return
      end

      if
        args.match == 'CodeCompanionChatCleared'
        and vim.api.nvim_buf_is_valid(bufnr)
      then
        local chat = require('codecompanion').buf_get_chat(bufnr)
        if chat then
          for _, winnr in ipairs(long_chat_windows(bufnr)) do
            replace_long_chat_fold(chat, winnr)
          end
        end
      end

      enabled_chat_buffers[bufnr] = nil
      for winnr, state in pairs(long_chat_folds) do
        if state.bufnr == bufnr then
          long_chat_folds[winnr] = nil
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      long_chat_folds[tonumber(args.match)] = nil
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(args)
      enabled_chat_buffers[args.buf] = nil
      for _, winnr in ipairs(long_chat_windows(args.buf)) do
        long_chat_folds[winnr] = nil
      end
    end,
  })
end

function M.toggle_long_chat(chat)
  if not chat or chat.bufnr ~= vim.api.nvim_get_current_buf() then
    return
  end

  if enabled_chat_buffers[chat.bufnr] then
    enabled_chat_buffers[chat.bufnr] = nil
    show_full_chat(chat)
    notify('Full chat shown; gF hides older lines')
    return
  end

  local line_count = vim.api.nvim_buf_line_count(chat.bufnr)
  if line_count <= RECENT_LINE_COUNT + MIN_HIDDEN_LINE_COUNT then
    notify(('Chat has %d lines; nothing hidden'):format(line_count))
    return
  end

  enabled_chat_buffers[chat.bufnr] = true
  local end_line = refresh_long_chat_folds(chat)
  if end_line then
    notify(('Older chat hidden (%d lines)'):format(end_line))
  else
    notify('No complete older messages to hide')
  end
end

function M.setup()
  setup_long_chat_autocmds()

  local ok, folds = pcall(require, 'codecompanion.interactions.chat.ui.folds')
  if not ok or folds._lpke_fold_text_patched then
    return
  end

  local original_fold_text = folds.fold_text

  folds.fold_text = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local fold_start = vim.v.foldstart - 1
    local state = long_chat_folds[vim.api.nvim_get_current_win()]

    if
      state
      and state.bufnr == bufnr
      and fold_start == 0
      and vim.v.foldend == state.end_line
    then
      return {
        {
          ('  %d older chat lines hidden (gF to show)'):format(state.end_line),
          'CodeCompanionChatFold',
        },
      }
    end

    local fold_data = folds.fold_summaries[bufnr]
      and folds.fold_summaries[bufnr][fold_start]

    if fold_data then
      return original_fold_text()
    end

    return default_fold_text()
  end

  folds._lpke_fold_text_patched = true
end

return M
