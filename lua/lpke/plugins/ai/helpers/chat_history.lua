local M = {}
local api = vim.api
local helpers = require('lpke.core.helpers')
local hints = require('lpke.plugins.ai.helpers.ui_hints')
local states = {}
local ns = api.nvim_create_namespace('LpkeChatHistory')
local RECENT_LINES = 300
local PAGE_LINES = 500
local HEADER_LINES = 4

local function close_view(state)
  if state.view and api.nvim_buf_is_valid(state.view) then
    api.nvim_buf_delete(state.view, { force = true })
  end
  state.view = nil
end

local function forget(bufnr)
  if states[bufnr] then
    close_view(states[bufnr])
    states[bufnr] = nil
  end
  if api.nvim_buf_is_valid(bufnr) then
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

local function render_page(state)
  local last = math.min(state.first + PAGE_LINES - 1, #state.lines)
  local page = math.floor((state.first - 1) / PAGE_LINES) + 1
  local pages = math.ceil(#state.lines / PAGE_LINES)
  local lines = {
    ('Page %d of %d · lines %d-%d of %d'):format(
      page,
      pages,
      state.first,
      last,
      #state.lines
    ),
  }
  local hint_rows = hints.append(lines, {
    { { 'H', 'older page' }, { 'L', 'newer page' }, { '/', 'search all' } },
    { { 'n/N', 'matches' }, { 'gF/q/Esc', 'close' } },
  })
  lines[#lines + 1] = ''
  for row = state.first, last do
    lines[#lines + 1] = state.lines[row]
  end
  vim.bo[state.view].modifiable = true
  api.nvim_buf_set_lines(state.view, 0, -1, false, lines)
  vim.bo[state.view].modifiable = false
  hints.apply(state.view, hint_rows)
  if state.win and api.nvim_win_is_valid(state.win) then
    local edge = page == pages and ' · newest'
      or page == 1 and ' · oldest'
      or ''
    api.nvim_win_set_config(state.win, {
      footer = {
        { (' Page %d / %d'):format(page, pages), 'DiagnosticInfo' },
        { edge .. ' ', 'Comment' },
      },
      footer_pos = 'right',
    })
  end
end

-- Parsed headings exclude quoted headers in code blocks. Keep at least the
-- latest exchange and the current draft, even when that exchange is large.
local function trim_range(chat, count)
  local query = vim.treesitter.query.get('markdown', 'chat')
  local root = chat.chat_parser:parse()[1]:root()
  local role = require('codecompanion.interactions.chat.helpers').format_role
  local headers = {}
  for id, node in query:iter_captures(root, chat.bufnr) do
    if
      query.captures[id] == 'role_only'
      and role(vim.treesitter.get_node_text(node, chat.bufnr))
        == chat.ui.roles.user
    then
      headers[#headers + 1] = node:range()
    end
  end
  local first = headers[1]
  for index = #headers - 1, 2, -1 do
    local row = headers[index]
    if row <= count - RECENT_LINES and row - first >= RECENT_LINES then
      return first, row
    end
  end
end

function M.compact(chat)
  if
    not chat
    or chat.current_request
    or (chat.status and chat.status ~= '')
    or not api.nvim_buf_is_valid(chat.bufnr)
  then
    return
  end
  local bufnr = chat.bufnr
  local count = api.nvim_buf_line_count(bufnr)
  if count <= RECENT_LINES * 2 then
    return
  end
  local first, last = trim_range(chat, count)
  if not first or last >= chat.header_line then
    return
  end

  local state = states[bufnr] or { lines = {} }
  states[bufnr] = state
  vim.list_extend(
    state.lines,
    api.nvim_buf_get_lines(bufnr, first, last, false)
  )
  local removed = last - first
  local views = {}
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    views[win] = api.nvim_win_call(win, vim.fn.winsaveview)
  end

  -- Deleted extmarks otherwise pile up on the first retained row.
  for _, namespace in pairs(api.nvim_get_namespaces()) do
    api.nvim_buf_clear_namespace(bufnr, namespace, first, last)
  end
  local modifiable, modified = vim.bo[bufnr].modifiable, vim.bo[bufnr].modified
  local undo = vim.bo[bufnr].undolevels
  vim.bo[bufnr].modifiable = true
  -- Undo must not resurrect archived lines or invalidate the parser offsets.
  vim.bo[bufnr].undolevels = -1
  api.nvim_buf_set_lines(bufnr, first, last, false, {})
  vim.bo[bufnr].undolevels = undo
  vim.bo[bufnr].modifiable = modifiable
  vim.bo[bufnr].modified = modified
  chat.header_line = chat.header_line - removed

  local function shift(row)
    return row < first and row or math.max(first, row - removed)
  end
  for _, key in ipairs({
    'last_write_start',
    'last_write_end',
    'current_section_start',
    'last_section_start',
  }) do
    local builder = chat.builder and chat.builder.state
    if builder and builder[key] then
      builder[key] = shift(builder[key])
    end
  end
  if chat.ui.cursor.pos then
    chat.ui.cursor.pos[1] = shift(chat.ui.cursor.pos[1] - 1) + 1
  end
  local summaries = chat.ui.folds.fold_summaries[bufnr]
  if summaries then
    local shifted = {}
    for row, summary in pairs(summaries) do
      if row < first or row >= last then
        shifted[shift(row)] = summary
      end
    end
    chat.ui.folds.fold_summaries[bufnr] = shifted
  end
  for win, view in pairs(views) do
    view.lnum = shift(view.lnum - 1) + 1
    view.topline = shift(view.topline - 1) + 1
    api.nvim_win_call(win, function()
      vim.fn.winrestview(view)
    end)
  end
  api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  api.nvim_buf_set_extmark(bufnr, ns, first, 0, {
    virt_lines_above = true,
    virt_lines = {
      {
        {
          ('Older chat: %d lines · gF to browse'):format(#state.lines),
          'Comment',
        },
      },
    },
  })
  if state.view and api.nvim_buf_is_valid(state.view) then
    render_page(state)
  end
end

function M.toggle(chat)
  if not chat then
    return
  end
  M.compact(chat)
  local state = states[chat.bufnr]
  if not state then
    vim.notify(
      'No older turns to browse yet',
      vim.log.levels.INFO,
      { title = 'CodeCompanion' }
    )
    return
  end
  if state.view and api.nvim_buf_is_valid(state.view) then
    close_view(state)
    return
  end

  local float = Lpke_new_float({
    title = ' Older chat ',
    border = 'rounded',
    width = '0.85w',
    height = '0.8h',
    max_width = 120,
    win_opts = { wrap = true, linebreak = true },
  })
  state.view = float.buf
  state.win = float.win
  state.first = math.floor((#state.lines - 1) / PAGE_LINES) * PAGE_LINES + 1
  vim.bo[state.view].bufhidden = 'wipe'
  vim.bo[state.view].filetype = 'markdown'
  render_page(state)
  local maps = {}
  local function search(direction)
    if not state.pattern or not api.nvim_win_is_valid(float.win) then
      return
    end
    local ok, regex = pcall(vim.regex, state.pattern)
    if not ok then
      vim.notify('Invalid search pattern', vim.log.levels.WARN)
      return
    end
    local row = state.first
      + api.nvim_win_get_cursor(float.win)[1]
      - HEADER_LINES
      - 1
    for offset = 1, #state.lines do
      local candidate = (row - 1 + offset * direction) % #state.lines + 1
      local col = regex:match_str(state.lines[candidate])
      if col then
        state.first = math.floor((candidate - 1) / PAGE_LINES) * PAGE_LINES + 1
        render_page(state)
        api.nvim_win_set_cursor(
          float.win,
          { candidate - state.first + HEADER_LINES + 1, col }
        )
        return
      end
    end
    vim.notify('Pattern not found in older chat', vim.log.levels.INFO)
  end
  maps[#maps + 1] = {
    'n!',
    '/',
    function()
      vim.ui.input({ prompt = 'Search older chat: ' }, function(pattern)
        if pattern and pattern ~= '' then
          state.pattern = pattern
          search(1)
        end
      end)
    end,
    { buffer = state.view, desc = 'Older chat: Search all pages' },
  }
  for key, direction in pairs({ n = 1, N = -1 }) do
    maps[#maps + 1] = {
      'n!',
      key,
      function()
        search(direction)
      end,
      { buffer = state.view, desc = 'Older chat: Find match' },
    }
  end
  for _, key in ipairs({ 'gF', 'q', '<Esc>' }) do
    maps[#maps + 1] = {
      'n!',
      key,
      function()
        close_view(state)
      end,
      { buffer = state.view, desc = 'Older chat: Close' },
    }
  end
  for key, direction in pairs({ H = -1, L = 1, ['[p'] = -1, [']p'] = 1 }) do
    maps[#maps + 1] = {
      'n!',
      key,
      function()
        state.first = math.max(
          1,
          math.min(
            math.floor((#state.lines - 1) / PAGE_LINES) * PAGE_LINES + 1,
            state.first + direction * PAGE_LINES * vim.v.count1
          )
        )
        render_page(state)
        api.nvim_win_set_cursor(float.win, { HEADER_LINES + 1, 0 })
      end,
      { buffer = state.view, desc = 'Older chat: Change page' },
    }
  end
  helpers.keymap_set_multi(maps)
  api.nvim_win_set_cursor(float.win, { HEADER_LINES + 1, 0 })
end

function M.setup()
  local Chat = require('codecompanion.interactions.chat')
  local UI = require('codecompanion.interactions.chat.ui')
  if Chat._lpke_chat_history then
    return
  end
  Chat._lpke_chat_history = true
  local submit, render = Chat.submit, UI.render
  Chat.submit = function(self, ...)
    M.compact(self)
    return submit(self, ...)
  end
  UI.render = function(self, ...)
    forget(self.chat_bufnr)
    return render(self, ...)
  end
  local group = api.nvim_create_augroup('LpkeChatHistory', { clear = true })
  api.nvim_create_autocmd('User', {
    group = group,
    pattern = {
      'CodeCompanionChatCreated',
      'CodeCompanionChatOpened',
      'CodeCompanionChatDone',
      'CodeCompanionChatStopped',
      'CodeCompanionChatRestored',
      'CodeCompanionACPChatRestored',
    },
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if bufnr then
        vim.schedule(function()
          M.compact(Chat.buf_get_chat(bufnr))
        end)
      end
    end,
  })
  api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(args)
      forget(args.buf)
    end,
  })
end

return M
