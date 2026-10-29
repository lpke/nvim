local M = {}

local chats = require('lpke.plugins.ai.helpers.chat_registry')
local source = require('lpke.plugins.ai.helpers.chat_source')
M.setup_source_buffer_tracking = source.setup
M.insert_last_source_path = source.insert
local DETACHED_CHAT_BUF_VAR = 'lpke_cc_detached_tab'
local DETACHED_CHAT_WIN_VAR = 'lpke_cc_detached_win'
local DETACHED_WINDOW_OPTS = {
  layout = 'tab',
  opts = {
    number = false,
    relativenumber = false,
  },
}

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

local function new_chat_msg(prefix)
  return string.format('%s (%d)', prefix, #chats.list())
end

local function buf_visible(bufnr)
  return bufnr
    and vim.api.nvim_buf_is_valid(bufnr)
    and #vim.fn.win_findbuf(bufnr) > 0
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

  local chat = chats.get(bufnr)
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
    buf = chat.bufnr,
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
  if opts.acp_session_id then
    -- The public chat wrapper drops ACP session arguments before Chat.new.
    opts.adapter = opts.params and opts.params.adapter
    opts.params = nil
    opts.buffer_context =
      require('codecompanion.utils.context').get(vim.api.nvim_get_current_buf())
    return require('codecompanion.interactions.chat').new(opts)
  end
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
end

local function hide_chat_window(chat)
  local win = chat and chat.ui and chat.ui.winnr
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_hide, win)
  end
end

function M.restore_context_from_current()
  local chat = chats.get()
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
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == target_chat.bufnr then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
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
  for _, chat in ipairs(chats.list()) do
    if not M.is_detached_chat_buf(chat.bufnr) then
      return chat
    end
  end
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

  local entries = chats.list()
  local total = #entries
  local idx = chat_index(bufnr, entries)

  if not idx or total == 0 then
    return nil
  end

  return idx, total
end

function M.insert_context_text(text)
  put_text(text)
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
  local chat = chats.get(bufnr)
  if
    not chat or not require('lpke.plugins.ai.helpers.chat_draft').empty(chat)
  then
    return false
  end
  local system_role = require('codecompanion.config').constants.SYSTEM_ROLE
  for _, message in ipairs(chat.messages or {}) do
    if
      message.role ~= system_role
      and not (message.opts and message.opts.visible == false)
    then
      for _, content in ipairs({
        message.content or '',
        message.reasoning or '',
      }) do
        if
          (type(content) == 'string' and vim.trim(content) ~= '')
          or (type(content) == 'table' and not vim.tbl_isempty(content))
        then
          return false
        end
      end
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
          and not M.is_detached_chat_buf(buf)
        then
          vim.api.nvim_win_close(win, false)
          break
        end
      end
    end
  end
end

-- Toggle the reusable sidebar chat.
function M.toggle_chat()
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
  vim.cmd('stopinsert')
end

-- Always open a new chat in the current chat layout.
function M.open_new_chat(opts)
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
  notify_later(
    new_chat_msg(from_detached_chat and 'New fullscreen chat' or 'New chat')
  )
  follow_chat(chat)
  vim.cmd('stopinsert')
end

function M.open_fullscreen_chat(opts)
  opts = opts or {}
  local current_chat = chats.get()

  if
    not opts.acp_session_id
    and vim.bo.filetype == 'codecompanion'
    and current_chat
  then
    if M.is_detached_chat_buf(current_chat.bufnr) then
      notify('Already in detached tab')
      return current_chat
    end

    current_chat.ui:hide()
    open_detached_chat(current_chat)
    notify('Fullscreen chat')
    return current_chat
  end

  vim.g.lpke_cc_chat_create_notified = true
  local chat = create_hidden_chat({
    hidden = true,
    window_opts = DETACHED_WINDOW_OPTS,
    params = opts.adapter and { adapter = opts.adapter } or nil,
    acp_session_id = opts.acp_session_id,
    acp_connection_only = opts.acp_connection_only,
    restore_acp_session = opts.restore_acp_session,
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
  if not opts.silent then
    notify_later(new_chat_msg('Fullscreen chat'))
  end
  follow_chat(chat)
  return chat
end

local function capture_selection()
  vim.cmd('normal! "vy')
  return vim.fn.getreg('v'), vim.bo.filetype
end

local function append_selection(selection, filetype)
  if selection == '' or vim.bo.filetype ~= 'codecompanion' then
    return false
  end
  vim.cmd('normal! Go')
  vim.api.nvim_put(M.build_code_block(selection, filetype), 'l', true, true)
  vim.cmd('normal! 2o')
  follow_chat(chats.get(0))
  vim.cmd('stopinsert')
  return true
end

function M.open_fullscreen_chat_with_context_selection()
  local selection, filetype = capture_selection()
  M.open_fullscreen_chat()
  append_selection(selection, filetype)
end

function M.open_new_chat_with_context_selection()
  if M.toggle_if_already_in_chat() then
    return
  end
  local selection, filetype = capture_selection()
  vim.g.lpke_cc_chat_create_notified = true
  open_sidebar_chat(create_hidden_chat())
  notify_later(new_chat_msg('New chat with selection'))
  append_selection(selection, filetype)
end

function M.toggle_chat_with_context_selection()
  if M.toggle_if_already_in_chat() then
    return
  end
  local selection, filetype = capture_selection()
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
  if append_selection(selection, filetype) then
    notify('Chat selection added')
  end
end

function M.open_inline_prompt_with_context(opts)
  if
    vim.bo.filetype == 'codecompanion'
    or vim.bo.filetype == 'codecompanion_input'
  then
    return
  end
  return require('lpke.plugins.ai.helpers.inline').open(opts)
end

function M.swap_chat(chat, direction)
  local entries = chats.list()
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
  local target = entries[next_idx]
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

function M.delete_current_chat(chat, opts)
  chat = chat or chats.get(0)
  if not chat then
    return
  end

  local others = vim.tbl_filter(function(other)
    return other ~= chat
  end, chats.list())

  local save_id = chat.opts and chat.opts.save_id
  if save_id then
    pcall(function()
      require('codecompanion').extensions.history.delete_chat(save_id)
    end)
  end

  if opts and opts.hidden then
    chat:close()
    if #others == 0 then
      create_hidden_chat()
    end
    notify('Chat deleted')
    return
  end

  if #others > 0 then
    local target = others[1]
    pcall(function()
      if chat.ui then
        chat.ui:hide()
      end
      if target.ui then
        if M.is_detached_chat_buf(target.bufnr) then
          M.focus_detached_chat(target)
        else
          open_sidebar_chat(target)
        end
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
