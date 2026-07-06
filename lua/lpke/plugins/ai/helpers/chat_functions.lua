local M = {}

local helpers = require('lpke.core.helpers')
local model_swap = require('lpke.plugins.ai.helpers.model_swap')

local DEFAULT_HTTP_TOOL_LINES = {
  '@{agent} @{fetch_webpage} @{web_search}',
}

local EMPTY_CHAT_TRAILING_BLANKS = 2
local DETACHED_CHAT_BUF_VAR = 'lpke_cc_detached_tab'
local DETACHED_CHAT_WIN_VAR = 'lpke_cc_detached_win'
local DETACHED_WINDOW_OPTS = {
  layout = 'tab',
  opts = {
    number = false,
    relativenumber = false,
  },
}

local DEFAULT_HTTP_TOOL_LINE_SET = {}
for _, line in ipairs(DEFAULT_HTTP_TOOL_LINES) do
  DEFAULT_HTTP_TOOL_LINE_SET[line] = true
end

local last_source_bufnr
local source_tracker_started = false

local function put_text(text)
  vim.api.nvim_put({ text }, 'c', vim.fn.mode() == 'n', true)
end

local function notify(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = 'CodeCompanion' })
end

local function notify_later(msg)
  vim.defer_fn(function()
    notify(msg)
  end, 20)
end

local function open_chats()
  local ok, codecompanion = pcall(require, 'codecompanion')
  if not ok or type(codecompanion.buf_get_chat) ~= 'function' then
    return {}
  end

  local chats = {}
  for _, item in ipairs(codecompanion.buf_get_chat() or {}) do
    if item.chat then
      table.insert(chats, item.chat)
    end
  end
  return chats
end

local function new_chat_msg(prefix)
  return string.format('%s (%d)', prefix, #open_chats())
end

local function sorted_chat_entries(opts)
  opts = opts or {}
  local registry = require('codecompanion.interactions.shared.registry')
  local entries = vim.tbl_filter(function(entry)
    return entry.interaction == 'chat'
      and (opts.detached ~= false or not M.is_detached_chat_buf(entry.bufnr))
  end, registry.list())

  table.sort(entries, function(a, b)
    return a.bufnr < b.bufnr
  end)

  return entries
end

local function buf_visible(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if vim.api.nvim_win_get_buf(win) == bufnr then
        return true
      end
    end
  end
  return false
end

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

function M.setup_source_buffer_tracking()
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

function M.is_detached_chat_buf(bufnr)
  bufnr = bufnr or 0
  if bufnr ~= 0 and not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  return vim.b[bufnr or 0][DETACHED_CHAT_BUF_VAR] == true
end

local function detached_win(bufnr)
  bufnr = bufnr or 0
  if bufnr ~= 0 and not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  return vim.b[bufnr or 0][DETACHED_CHAT_WIN_VAR]
end

local function detached_win_valid(bufnr)
  local win = detached_win(bufnr)
  return win
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_buf(win) == bufnr
end

local function current_win_is_detached_tab(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return M.is_detached_chat_buf(bufnr)
    and detached_win_valid(bufnr)
    and vim.api.nvim_get_current_win() == detached_win(bufnr)
end

local function hide_current_sidebar_chat()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= 'codecompanion' then
    return
  end

  if current_win_is_detached_tab(bufnr) then
    return
  end

  pcall(vim.api.nvim_win_hide, vim.api.nvim_get_current_win())
end

local function unmark_detached_chat(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.b[bufnr][DETACHED_CHAT_BUF_VAR] = false
  vim.b[bufnr][DETACHED_CHAT_WIN_VAR] = nil

  local chat = require('codecompanion').buf_get_chat(bufnr)
  if chat and chat.ui then
    chat.ui.window_opts = nil
  end
end

local function mark_detached_chat(chat)
  if not chat or not chat.bufnr then
    return
  end
  vim.b[chat.bufnr][DETACHED_CHAT_BUF_VAR] = true

  local group = vim.api.nvim_create_augroup(
    'LpkeCodeCompanionDetached:' .. chat.bufnr,
    { clear = true }
  )
  vim.api.nvim_create_autocmd({ 'BufWinLeave', 'BufDelete', 'BufWipeout' }, {
    group = group,
    buffer = chat.bufnr,
    callback = function(args)
      vim.schedule(function()
        if not detached_win_valid(args.buf) or not buf_visible(args.buf) then
          unmark_detached_chat(args.buf)
        end
      end)
    end,
  })
end

local function follow_chat(chat)
  if not (chat and chat.ui and chat.ui:is_visible()) then
    return
  end

  chat.ui.cursor.has_moved = false
  chat.ui.cursor.pos = nil
  chat.ui:follow()
end

local function open_detached_chat(chat, opts)
  opts = opts or {}
  if not chat or not chat.ui then
    return
  end

  mark_detached_chat(chat)
  if opts.win and vim.api.nvim_win_is_valid(opts.win) then
    vim.api.nvim_set_current_win(opts.win)
    chat.ui:open({
      window_opts = vim.tbl_deep_extend('force', {}, DETACHED_WINDOW_OPTS, {
        layout = 'buffer',
      }),
    })
  else
    chat.ui:open({ window_opts = DETACHED_WINDOW_OPTS })
  end
  vim.b[chat.bufnr][DETACHED_CHAT_WIN_VAR] = chat.ui.winnr
  follow_chat(chat)
  vim.cmd('stopinsert')
end

function M.focus_detached_chat(chat)
  if not chat or not chat.ui then
    return false
  end

  mark_detached_chat(chat)

  local win = detached_win(chat.bufnr)
  if win and vim.api.nvim_win_is_valid(win) then
    local tab = vim.api.nvim_win_get_tabpage(win)
    vim.api.nvim_set_current_tabpage(tab)
    vim.api.nvim_set_current_win(win)
    vim.cmd('stopinsert')
    return true
  end

  open_detached_chat(chat)
  return true
end

local function open_sidebar_chat(chat)
  if not chat or not chat.ui then
    return
  end

  if chat.ui:is_visible() and not M.is_detached_chat_buf(chat.bufnr) then
    chat.ui:hide()
  end
  hide_current_sidebar_chat()
  chat.ui:open({ window_opts = { default = true }, toggled = true })
  vim.cmd('stopinsert')
end

local function create_hidden_chat(opts)
  opts = vim.tbl_extend('keep', opts or {}, {
    auto_submit = false,
    hidden = true,
  })
  return require('codecompanion').chat(opts)
end

local function is_disposable_empty_chat(chat)
  if
    not chat
    or not chat.bufnr
    or not vim.api.nvim_buf_is_valid(chat.bufnr)
    or not vim.api.nvim_buf_is_loaded(chat.bufnr)
  then
    return false
  end

  if chat.current_request or chat.current_tool then
    return false
  end

  return M.is_empty_chat(chat.bufnr)
    or M.is_chat_only_http_tool_context(chat.bufnr)
end

local function hide_chat_window(chat)
  local win = chat and chat.ui and chat.ui.winnr
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_hide, win)
  end
end

function M.restore_context_from_current()
  local ok, codecompanion = pcall(require, 'codecompanion')
  if not ok or type(codecompanion.buf_get_chat) ~= 'function' then
    return nil
  end

  local chat = codecompanion.buf_get_chat(0)
  if not chat then
    return nil
  end

  return {
    source_chat = chat,
    source_bufnr = chat.bufnr,
    source_detached = current_win_is_detached_tab(chat.bufnr),
    close_source = is_disposable_empty_chat(chat),
  }
end

function M.capture_restore_context()
  local ctx = M.restore_context_from_current()
  if ctx then
    M._pending_restore_context = ctx
  end
  return M._pending_restore_context
end

function M.take_restore_context()
  local ctx = M._pending_restore_context
  M._pending_restore_context = nil
  return ctx
end

function M.after_restore(target_chat, ctx)
  if not target_chat then
    return
  end

  ctx = ctx or M.take_restore_context()
  if not ctx then
    return
  end

  if ctx.source_detached then
    if target_chat == ctx.source_chat then
      M.focus_detached_chat(target_chat)
    elseif ctx.close_source then
      hide_chat_window(target_chat)
      open_detached_chat(target_chat, { win = detached_win(ctx.source_bufnr) })
    else
      hide_chat_window(target_chat)
      open_detached_chat(target_chat)
    end
  end

  if
    ctx.close_source
    and ctx.source_chat
    and ctx.source_chat ~= target_chat
  then
    vim.defer_fn(function()
      local source_bufnr = ctx.source_chat.bufnr
      local ok_lifecycle, lifecycle =
        pcall(require, 'lpke.plugins.ai.helpers.acp_lifecycle')
      if
        ok_lifecycle
        and type(lifecycle.suspend_chat) == 'function'
        and lifecycle.suspend_chat(ctx.source_chat, {
          stop_request = true,
          delay_ms = 100,
        })
      then
        vim.defer_fn(function()
          if source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
            pcall(function()
              ctx.source_chat:close()
            end)
          end
        end, 300)
        return
      end

      pcall(function()
        ctx.source_chat:close()
      end)
    end, 1000)
  end
end

function M.open_history()
  M.capture_restore_context()
  vim.cmd('CodeCompanionHistory')
end

local function first_sidebar_chat()
  local ok, codecompanion = pcall(require, 'codecompanion')
  if not ok or type(codecompanion.buf_get_chat) ~= 'function' then
    return nil
  end

  for _, entry in ipairs(sorted_chat_entries({ detached = false })) do
    local chat = codecompanion.buf_get_chat(entry.bufnr)
    if chat then
      return chat
    end
  end
  return nil
end

local function visible_sidebar_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if
      vim.api.nvim_buf_is_loaded(buf)
      and vim.api.nvim_get_option_value('filetype', { buf = buf }) == 'codecompanion'
      and not M.is_detached_chat_buf(buf)
    then
      return win
    end
  end
  return nil
end

local function chat_index(bufnr, entries)
  for i, entry in ipairs(entries) do
    if entry.bufnr == bufnr then
      return i
    end
  end
  return nil
end

function M.chat_position(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local entries = sorted_chat_entries()
  local total = #entries
  local idx = chat_index(bufnr, entries)

  if not idx or total == 0 then
    return nil
  end

  return idx, total
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

function M.insert_last_source_path()
  M.setup_source_buffer_tracking()

  local path = source_path()
  if not path then
    notify('No source buffer path available')
    return
  end

  insert_text_at_cursor(escaped_path_text(path))
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
    if M.is_detached_chat_buf(0) then
      return false
    end
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
    local changed = M.remove_http_tool_context(bufnr)
    if changed then
      notify('Chat tools removed')
    end
    return changed
  end

  if
    model_swap.is_acp_adapter(from_adapter)
    and model_swap.is_http_adapter(to_adapter)
    and M.is_empty_chat(bufnr)
  then
    local changed = M.add_http_tool_context(bufnr)
    if changed then
      notify('Chat tools added')
    end
    return changed
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
          and not M.is_detached_chat_buf(buf)
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

  local cc_win = visible_sidebar_win()
  if cc_win then
    pcall(vim.api.nvim_win_hide, cc_win)
    return
  end

  local chat = first_sidebar_chat() or create_hidden_chat()
  open_sidebar_chat(chat)
  if
    vim.bo.filetype == 'codecompanion'
    and M.is_empty_chat(vim.api.nvim_get_current_buf())
  then
    vim.cmd('normal! G')
    if M.insert_http_tools() then
      vim.cmd('normal! G2o')
      notify('Chat tools added')
    end
  end
  vim.cmd('stopinsert')
end

-- Always open a new chat, adding HTTP tools only for HTTP adapters.
function M.open_new_chat_with_tools(opts)
  opts = opts or {}
  local from_detached_chat = vim.bo.filetype == 'codecompanion'
    and M.is_detached_chat_buf(0)
  if not opts.from_chat_keymap and M.toggle_if_already_in_chat() then
    return
  end
  vim.g.lpke_cc_chat_create_notified = true
  local chat = create_hidden_chat()
  if from_detached_chat then
    open_detached_chat(chat)
  else
    open_sidebar_chat(chat)
  end
  if M.insert_http_tools() then
    vim.cmd('normal! G2o')
    follow_chat(chat)
    notify_later(
      new_chat_msg(
        from_detached_chat and 'New fullscreen chat with tools'
          or 'New chat with tools'
      )
    )
  else
    notify_later(
      new_chat_msg(from_detached_chat and 'New fullscreen chat' or 'New chat')
    )
  end
  follow_chat(chat)
  vim.cmd('stopinsert')
end

function M.open_fullscreen_chat(opts)
  opts = opts or {}
  local chat_module = require('codecompanion.interactions.chat')
  local current_chat = chat_module.buf_get_chat(0)

  if vim.bo.filetype == 'codecompanion' and current_chat then
    if M.is_detached_chat_buf(current_chat.bufnr) then
      notify('Already in detached tab')
      return
    end

    current_chat.ui:hide()
    open_detached_chat(current_chat)
    notify('Fullscreen chat')
    return
  end

  vim.g.lpke_cc_chat_create_notified = true
  local chat = create_hidden_chat({
    hidden = true,
    window_opts = DETACHED_WINDOW_OPTS,
  })

  if not chat then
    notify('Fullscreen chat failed')
    return
  end

  open_detached_chat(
    chat,
    opts.replace_current_window and { win = vim.api.nvim_get_current_win() }
      or nil
  )
  if not opts.skip_initial_tools and M.insert_http_tools() then
    vim.cmd('normal! G2o')
    follow_chat(chat)
    if not opts.silent then
      notify_later(new_chat_msg('Fullscreen chat with tools'))
    end
  else
    if not opts.silent then
      notify_later(new_chat_msg('Fullscreen chat'))
    end
  end
  follow_chat(chat)
end

function M.open_fullscreen_chat_with_context_selection()
  vim.cmd('normal! "vy')
  local selection = vim.fn.getreg('v')
  local filetype = vim.bo.filetype

  M.open_fullscreen_chat({ skip_initial_tools = true })

  if selection == '' or vim.bo.filetype ~= 'codecompanion' then
    return
  end

  vim.cmd(M.insert_http_tools() and 'normal! 2o' or 'normal! Go')
  vim.api.nvim_put(M.build_code_block(selection, filetype), 'l', true, true)
  vim.cmd('normal! 2o')
  local chat = require('codecompanion').buf_get_chat(0)
  follow_chat(chat)
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
  vim.g.lpke_cc_chat_create_notified = true
  local chat = create_hidden_chat()
  open_sidebar_chat(chat)
  local inserted_tools = M.insert_http_tools()
  notify_later(
    new_chat_msg(
      inserted_tools and 'New chat with selection/tools'
        or 'New chat with selection'
    )
  )
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
      notify('Chat selection added with tools')
    else
      vim.cmd('normal! Go')
      notify('Chat selection added')
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

function M.swap_chat(chat, direction)
  local entries = sorted_chat_entries()
  local total = #entries
  if total <= 1 then
    notify('No other chats')
    return
  end

  local current_idx = chat_index(chat.bufnr, entries)
  if not current_idx then
    notify('Chat not found')
    return
  end

  local next_idx = direction > 0 and (current_idx % total) + 1
    or ((current_idx - 2 + total) % total) + 1
  local next_entry = entries[next_idx]
  local target = next_entry
    and require('codecompanion').buf_get_chat(next_entry.bufnr)
  if not (target and target.ui) then
    notify('Chat not found')
    return
  end

  if M.is_detached_chat_buf(target.bufnr) then
    if not current_win_is_detached_tab(chat.bufnr) then
      hide_current_sidebar_chat()
    end
    M.focus_detached_chat(target)
  else
    open_sidebar_chat(target)
  end

  notify(string.format('Chat %d/%d', next_idx, total))
end

function M.delete_current_chat(chat)
  chat = chat or require('codecompanion.interactions.chat').buf_get_chat(0)
  if not chat then
    return
  end

  local others = vim.tbl_filter(function(other)
    return other ~= chat
  end, open_chats())

  local save_id = chat.opts and chat.opts.save_id
  if save_id then
    pcall(function()
      require('codecompanion').extensions.history.delete_chat(save_id)
    end)
  end

  if #others > 0 then
    local target = others[1]
    pcall(function()
      if chat.ui then
        chat.ui:hide()
      end
      if target.ui then
        target.ui:open()
      end
    end)
    chat:close()
    notify('Chat deleted')
    return
  end

  chat:close()
  vim.g.lpke_cc_chat_create_notified = true
  vim.cmd('CodeCompanionChat')
  notify_later(new_chat_msg('Chat deleted; new chat'))
end

return M
