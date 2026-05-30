local M = {}

local setup_done = false
local preview_ns =
  vim.api.nvim_create_namespace('LpkeCodeCompanionHistorySearchPreview')

local history_acp = require('lpke.plugins.ai.helpers.history_acp')
local history_scope = require('lpke.plugins.ai.helpers.history_scope')
local active_match_hl = 'LpkeCodeCompanionHistorySearchActiveMatch'
local inactive_match_hl = 'TelescopePreviewMatch'

local function history()
  return require('codecompanion').extensions.history
end

local function chat_title(chat)
  return chat.title or chat.name or chat.save_id or 'Untitled'
end

local function display_title(chat)
  local marker = history_acp.format_session_id(chat.acp_session_id)
  if marker then
    return marker .. ' ' .. chat_title(chat)
  end
  return chat_title(chat)
end

local message_content = history_scope.message_content
local searchable_message = history_scope.searchable_message

local function load_chats()
  local items = history().get_chats()
  local chats = {}

  for save_id, meta in pairs(items or {}) do
    local chat = history().load_chat(save_id)
    if chat then
      chat.acp_session_id = chat.acp_session_id or meta.acp_session_id
      chat.cwd = chat.cwd or meta.cwd
      chat.project_root = chat.project_root or meta.project_root
      table.insert(chats, chat)
    end
  end

  table.sort(chats, function(a, b)
    return (a.updated_at or 0) > (b.updated_at or 0)
  end)

  return chats
end

local search_pattern = history_scope.search_pattern
local match_col = history_scope.match_col

local function line_matches(line, pattern)
  return history_scope.line_matches(line, pattern)
end

local function each_match(line, pattern, callback)
  local from_col = 0

  while true do
    local start_col, end_col = match_col(line, pattern, from_col)
    if not start_col then
      break
    end

    callback(start_col, end_col)
    from_col = math.max(end_col, start_col + 1)
    if from_col > #line then
      break
    end
  end
end

local function highlight_matches(bufnr, lines, query, ignorecase, active_match)
  vim.api.nvim_buf_clear_namespace(bufnr, preview_ns, 0, -1)
  local pattern = search_pattern(query, ignorecase)
  if not pattern then
    return
  end

  for lnum, line in ipairs(lines) do
    local is_active_line = active_match and active_match.lnum == lnum
    each_match(line, pattern, function(start_col, end_col)
      vim.api.nvim_buf_set_extmark(bufnr, preview_ns, lnum - 1, start_col, {
        end_col = end_col,
        hl_group = is_active_line and active_match_hl or inactive_match_hl,
        priority = is_active_line and 300 or 200,
      })
    end)
  end
end

local function normalize_line(line)
  return (line or ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
end

local function chat_scope_matches(chat, parsed, project_root)
  return parsed.all_chats or history_scope.in_project(chat, project_root)
end

local function chat_entries(chats, parsed, opts)
  if not parsed.explicit_scope then
    return {}
  end

  opts = opts or {}
  local max_results = opts.max_results or 500
  local project_root = opts.project_root or history_scope.current_project_root()
  local results = {}

  for _, chat in ipairs(chats) do
    if chat_scope_matches(chat, parsed, project_root) then
      table.insert(results, {
        chat = chat,
        display_title = display_title(chat),
        ignorecase = true,
        line_number = 0,
        query = '',
        role = 'chat',
        save_id = chat.save_id,
        text = chat_title(chat),
        title = chat_title(chat),
      })

      if #results >= max_results then
        break
      end
    end
  end

  return results
end

local function search_chats(chats, parsed, opts)
  parsed = type(parsed) == 'table' and parsed
    or history_scope.parse_chat_search_prompt(parsed)

  local prompt = vim.trim(parsed.search or '')
  if prompt == '' then
    return chat_entries(chats, parsed, opts)
  end

  opts = opts or {}
  local max_results = opts.max_results or 500
  local max_matches_per_chat = opts.max_matches_per_chat or 20
  local project_root = opts.project_root or history_scope.current_project_root()
  local pattern = search_pattern(prompt)
  if not pattern then
    return {}
  end
  local results = {}

  for _, chat in ipairs(chats) do
    if chat_scope_matches(chat, parsed, project_root) then
      local matches_for_chat = 0

      for msg_index, msg in ipairs(chat.messages or {}) do
        if searchable_message(msg) then
          local content = message_content(msg)
          for line_number, line in
            ipairs(vim.split(content, '\n', { plain = true }))
          do
            if line_matches(line, pattern) then
              matches_for_chat = matches_for_chat + 1
              table.insert(results, {
                chat = chat,
                save_id = chat.save_id,
                title = chat_title(chat),
                display_title = display_title(chat),
                role = msg.role or 'message',
                msg_index = msg_index,
                line_number = line_number,
                query = prompt,
                ignorecase = pattern.ignorecase,
                text = line,
              })

              if
                #results >= max_results
                or matches_for_chat >= max_matches_per_chat
              then
                break
              end
            end
          end
        end

        if
          #results >= max_results or matches_for_chat >= max_matches_per_chat
        then
          break
        end
      end
    end

    if #results >= max_results then
      break
    end
  end

  return results
end

local function open_chat(chat_data)
  local chat_module = require('codecompanion.interactions.chat')
  local codecompanion = require('codecompanion')
  local active_chat = codecompanion.last_chat()

  for _, data in ipairs(chat_module.buf_get_chat() or {}) do
    local chat = data.chat
    if chat and chat.opts and chat.opts.save_id == chat_data.save_id then
      if active_chat and active_chat ~= chat and active_chat.ui:is_active() then
        active_chat.ui:hide()
      end
      chat.ui:open()
      return chat
    end
  end

  local messages = vim.deepcopy(chat_data.messages or {})
  local last_msg = messages[#messages]
  if
    last_msg
    and (
      last_msg.role ~= 'user'
      or (last_msg.role == 'user' and (last_msg.opts or {}).visible == false)
    )
  then
    table.insert(messages, {
      role = 'user',
      content = '',
      opts = { visible = true },
    })
  end

  local context_utils = require('codecompanion.utils.context')
  local context = context_utils.get(vim.api.nvim_get_current_buf())
  local adapter = chat_data.adapter
  local settings = chat_data.settings or {}
  local ok, resolved = pcall(require('codecompanion.adapters').resolve, adapter)
  if not ok or not resolved then
    return vim.notify(
      string.format('Adapter %s is not available', adapter or 'unknown'),
      vim.log.levels.ERROR,
      { title = 'CodeCompanion' }
    )
  end

  local chat = chat_module.new({
    acp_session_id = chat_data.acp_session_id,
    adapter = adapter,
    buffer_context = context,
    messages = messages,
    save_id = chat_data.save_id,
    settings = settings,
    title = chat_data.title,
  })

  for _, item in ipairs(chat_data.context_items or chat_data.refs or {}) do
    chat.context:add(item)
  end

  chat.tool_registry.schemas = chat_data.schemas or {}
  chat.tool_registry.in_use = chat_data.in_use or {}
  chat.cycle = chat_data.cycle or 1
  chat.opts.title_refresh_count = chat_data.title_refresh_count or 0
  return chat
end

local function preview_lines(chat, target)
  local lines = {
    '---',
    'title: ' .. vim.inspect(chat_title(chat)),
    'adapter: ' .. vim.inspect(chat.adapter),
  }
  local target_lnum = nil
  local target_col = 0
  local pattern = target and search_pattern(target.query, target.ignorecase)

  if chat.acp_session_id then
    table.insert(
      lines,
      'acp_session_id: ' .. history_acp.format_session_id(chat.acp_session_id)
    )
  end

  table.insert(lines, '---')
  table.insert(lines, '')

  local last_role = nil
  for msg_index, msg in ipairs(chat.messages or {}) do
    if searchable_message(msg) then
      if msg.role ~= last_role then
        if last_role ~= nil then
          table.insert(lines, '')
        end
        table.insert(lines, '## ' .. (msg.role or 'message'))
        table.insert(lines, '')
        last_role = msg.role
      end

      for line_number, line in
        ipairs(vim.split(message_content(msg), '\n', { plain = true }))
      do
        local lnum = #lines + 1
        table.insert(lines, line)
        if
          target
          and target.msg_index == msg_index
          and target.line_number == line_number
        then
          local start_col = match_col(line, pattern)
          target_lnum = lnum
          target_col = start_col or 0
        end
      end
    end
  end

  return {
    lines = lines,
    target_lnum = target_lnum,
    target_col = target_col,
  }
end

local function jump_to_result(chat, result)
  if not (chat and chat.bufnr and vim.api.nvim_buf_is_valid(chat.bufnr)) then
    return
  end

  vim.schedule(function()
    local winid = vim.fn.bufwinid(chat.bufnr)
    if winid == -1 then
      return
    end

    local lines = vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false)
    local exact_line = normalize_line(result.text)
    local fallback_lnum = nil
    local fallback_col = 0
    local pattern = search_pattern(result.query, result.ignorecase)

    for lnum, line in ipairs(lines) do
      local col = match_col(line, pattern)
      if col and not fallback_lnum then
        fallback_lnum = lnum
        fallback_col = col
      end

      if col and normalize_line(line) == exact_line then
        pcall(vim.api.nvim_win_set_cursor, winid, { lnum, col })
        pcall(vim.api.nvim_win_call, winid, function()
          vim.cmd('normal! zz')
        end)
        return
      end
    end

    if fallback_lnum then
      pcall(vim.api.nvim_win_set_cursor, winid, {
        fallback_lnum,
        fallback_col,
      })
      pcall(vim.api.nvim_win_call, winid, function()
        vim.cmd('normal! zz')
      end)
    end
  end)
end

local function entry_maker(result)
  local line = normalize_line(result.text)
  if #line > 100 then
    line = line:sub(1, 97) .. '...'
  end

  local location = result.line_number > 0
      and string.format('%s:%d', result.role, result.line_number)
    or result.role
  local display =
    string.format('%s %s %s', result.display_title, location, line)

  return {
    value = result,
    display = display,
    ordinal = table.concat({
      result.display_title,
      result.role,
      result.text,
    }, ' '),
    save_id = result.save_id,
  }
end

function M.open(opts)
  opts = opts or {}
  local chats = load_chats()
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local finders = require('telescope.finders')
  local pickers = require('telescope.pickers')
  local previewers = require('telescope.previewers')
  local sorters = require('telescope.sorters')
  local project_root = history_scope.current_project_root()

  pickers
    .new(opts, {
      prompt_title = 'Find in Chats',
      initial_mode = opts.initial_mode or 'insert',
      default_text = opts.default_text,
      finder = finders.new_dynamic({
        fn = function(prompt)
          local parsed = history_scope.parse_chat_search_prompt(prompt)
          return search_chats(
            chats,
            parsed,
            vim.tbl_extend('force', opts, {
              project_root = project_root,
            })
          )
        end,
        entry_maker = entry_maker,
      }),
      previewer = previewers.new_buffer_previewer({
        title = 'Chat Preview',
        define_preview = function(self, entry)
          local chat = entry and entry.value and entry.value.chat
          if not chat then
            return
          end
          vim.bo[self.state.bufnr].filetype = 'text'
          vim.bo[self.state.bufnr].modifiable = true
          local preview = preview_lines(chat, entry.value)
          vim.api.nvim_buf_set_lines(
            self.state.bufnr,
            0,
            -1,
            false,
            preview.lines
          )
          if
            self.state.winid and vim.api.nvim_win_is_valid(self.state.winid)
          then
            pcall(vim.api.nvim_win_set_buf, self.state.winid, self.state.bufnr)
          end
          highlight_matches(
            self.state.bufnr,
            preview.lines,
            entry.value.query,
            entry.value.ignorecase,
            preview.target_lnum and { lnum = preview.target_lnum } or nil
          )
          vim.bo[self.state.bufnr].modifiable = false

          if preview.target_lnum and self.state.winid then
            local bufnr = self.state.bufnr
            local winid = self.state.winid
            local target_lnum = preview.target_lnum
            local target_col = preview.target_col or 0

            vim.schedule(function()
              if
                not vim.api.nvim_win_is_valid(winid)
                or not vim.api.nvim_buf_is_valid(bufnr)
              then
                return
              end

              if vim.api.nvim_win_get_buf(winid) ~= bufnr then
                return
              end

              pcall(vim.api.nvim_win_set_cursor, winid, {
                target_lnum,
                target_col,
              })
              pcall(vim.api.nvim_win_call, winid, function()
                vim.cmd('normal! zz')
              end)
            end)
          end
        end,
      }),
      sorter = sorters.highlighter_only(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection and selection.value and selection.value.chat then
            local chat = open_chat(selection.value.chat)
            jump_to_result(chat, selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

function M.open_from_telescope(prompt_bufnr)
  prompt_bufnr = prompt_bufnr or vim.api.nvim_get_current_buf()
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local picker = action_state.get_current_picker(prompt_bufnr)
  local prompt = picker and picker:_get_prompt() or ''
  actions.close(prompt_bufnr)
  M.open({ default_text = prompt })
end

local function back_to_history(prompt_bufnr)
  prompt_bufnr = prompt_bufnr or vim.api.nvim_get_current_buf()
  local actions = require('telescope.actions')
  actions.close(prompt_bufnr)
  vim.cmd('CodeCompanionHistory')
end

function M.setup()
  if setup_done then
    return
  end
  setup_done = true

  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors
  helpers.set_hl(active_match_hl, tc and {
    fg = tc.base,
    bg = tc.gold,
    bold = true,
  } or { link = 'CurSearch' })

  helpers.telescope_keymap_set_multi('^Saved Chats', {
    {
      'in',
      '<A-s>',
      M.open_from_telescope,
      { desc = 'CodeCompanion: Find in saved chats' },
    },
  })
  helpers.telescope_keymap_set_multi('^Find in Chats$', {
    {
      'in',
      '<A-s>',
      back_to_history,
      { desc = 'CodeCompanion: Saved chat list' },
    },
  })
end

return M
