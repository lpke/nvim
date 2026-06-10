local M = {}

local api = vim.api

local DRAFT_DIR = vim.fn.stdpath('data') .. '/codecompanion-drafts'
local DEBOUNCE_MS = 400

local timers = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'CodeCompanion' })
end

local function ensure_dir()
  vim.fn.mkdir(DRAFT_DIR, 'p')
end

local function cc_config()
  local ok, config = pcall(require, 'codecompanion.config')
  if ok then
    return config
  end

  return nil
end

local function user_role()
  local config = cc_config()
  if
    config
    and config.interactions
    and config.interactions.chat
    and config.interactions.chat.roles
    and type(config.interactions.chat.roles.user) == 'string'
  then
    return config.interactions.chat.roles.user
  end

  return 'Me'
end

local function cwd()
  return vim.fn.getcwd()
end

local function is_codecompanion_buf(bufnr)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local ok, filetype = pcall(function()
    return vim.bo[bufnr].filetype
  end)

  return ok and filetype == 'codecompanion'
end

local function draft_path()
  ensure_dir()
  return string.format(
    '%s/%d-%d-%d.json',
    DRAFT_DIR,
    os.time(),
    vim.fn.getpid(),
    math.random(100000, 999999)
  )
end

local function read_json(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then
    return nil
  end

  local decode_ok, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not decode_ok or type(data) ~= 'table' then
    return nil
  end

  return data
end

local function atomic_write(path, data)
  ensure_dir()

  local encoded = vim.json.encode(data)
  local tmp = path
    .. '.tmp.'
    .. vim.fn.getpid()
    .. '.'
    .. math.random(1000, 9999)
  local write_ok, write_result = pcall(vim.fn.writefile, { encoded }, tmp)
  if not write_ok or write_result ~= 0 then
    pcall(vim.fn.delete, tmp)
    return false
  end

  local rename_call_ok, rename_ok = pcall(vim.uv.fs_rename, tmp, path)
  if not rename_call_ok or not rename_ok then
    pcall(vim.fn.delete, tmp)
    return false
  end

  return true
end

local function delete_file(path)
  if type(path) == 'string' and path ~= '' then
    pcall(vim.fn.delete, path)
  end
end

local function get_buf_var(bufnr, key, fallback)
  local ok, value = pcall(api.nvim_buf_get_var, bufnr, key)
  if ok then
    return value
  end
  return fallback
end

local function set_buf_var(bufnr, key, value)
  if api.nvim_buf_is_valid(bufnr) then
    pcall(api.nvim_buf_set_var, bufnr, key, value)
  end
end

local function del_buf_var(bufnr, key)
  if api.nvim_buf_is_valid(bufnr) then
    pcall(api.nvim_buf_del_var, bufnr, key)
  end
end

local function set_or_del_list_var(bufnr, key, values)
  if #values > 0 then
    set_buf_var(bufnr, key, values)
  else
    del_buf_var(bufnr, key)
  end
end

local function draft_cwd(bufnr, path)
  local stored = get_buf_var(bufnr, 'lpke_cc_draft_cwd', nil)
  if type(stored) == 'string' and stored ~= '' then
    return stored
  end

  local data = path and read_json(path) or nil
  if data and type(data.cwd) == 'string' and data.cwd ~= '' then
    set_buf_var(bufnr, 'lpke_cc_draft_cwd', data.cwd)
    return data.cwd
  end

  local current = cwd()
  set_buf_var(bufnr, 'lpke_cc_draft_cwd', current)
  return current
end

local function open_codecompanion_buffers()
  local bufs = {}
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if is_codecompanion_buf(bufnr) then
      table.insert(bufs, bufnr)
    end
  end

  return bufs
end

local function primary_path(bufnr)
  return get_buf_var(bufnr, 'lpke_cc_draft_path', nil)
end

local function set_primary_path(bufnr, path)
  set_buf_var(bufnr, 'lpke_cc_draft_path', path)
end

local function delete_paths(bufnr)
  local paths = get_buf_var(bufnr, 'lpke_cc_draft_delete_paths', {})
  if type(paths) ~= 'table' then
    return {}
  end
  return paths
end

local function restored_paths(bufnr)
  local paths = get_buf_var(bufnr, 'lpke_cc_draft_restored_paths', {})
  if type(paths) ~= 'table' then
    return {}
  end
  return paths
end

local function path_in(paths, path)
  for _, existing in ipairs(paths) do
    if existing == path then
      return true
    end
  end

  return false
end

local function remove_path(paths, path)
  local next_paths = {}
  for _, existing in ipairs(paths) do
    if existing ~= path then
      table.insert(next_paths, existing)
    end
  end

  return next_paths
end

local function mark_path(marks, path, mark)
  if type(path) ~= 'string' or path == '' then
    return
  end

  if mark == 'this' or marks[path] ~= 'this' then
    marks[path] = mark
  end
end

local function add_delete_path(bufnr, path)
  if type(path) ~= 'string' or path == '' then
    return
  end

  local paths = delete_paths(bufnr)
  if path_in(paths, path) then
    return
  end

  table.insert(paths, path)
  set_buf_var(bufnr, 'lpke_cc_draft_delete_paths', paths)
end

local function add_restored_path(bufnr, path)
  if type(path) ~= 'string' or path == '' then
    return
  end

  local paths = restored_paths(bufnr)
  if path_in(paths, path) then
    return
  end

  table.insert(paths, path)
  set_buf_var(bufnr, 'lpke_cc_draft_restored_paths', paths)
end

local function clear_paths(bufnr)
  del_buf_var(bufnr, 'lpke_cc_draft_path')
  del_buf_var(bufnr, 'lpke_cc_draft_delete_paths')
  del_buf_var(bufnr, 'lpke_cc_draft_restored_paths')
  del_buf_var(bufnr, 'lpke_cc_draft_cwd')
end

local function is_header(line)
  return type(line) == 'string' and line:match('^##%s+') ~= nil
end

local function header_separator()
  local config = cc_config()
  return config
      and config.display
      and config.display.chat
      and config.display.chat.separator
    or '─'
end

local function role_header_matches(line, role)
  if type(line) ~= 'string' or type(role) ~= 'string' or role == '' then
    return false
  end

  local header = '## ' .. role
  if line == header then
    return true
  end

  return line:match(
    '^' .. vim.pesc(header) .. '%s+' .. vim.pesc(header_separator())
  ) ~= nil
end

local function is_user_header(line)
  return role_header_matches(line, user_role())
end

local function chat_for_buf(bufnr)
  local ok, chat_module = pcall(require, 'codecompanion.interactions.chat')
  if not ok or type(chat_module.buf_get_chat) ~= 'function' then
    return nil
  end

  return chat_module.buf_get_chat(bufnr)
end

local function visible_context_lines(bufnr)
  local chat = chat_for_buf(bufnr)
  if not chat or type(chat.context_items) ~= 'table' then
    return nil
  end

  local config = cc_config()
  local icons = config
      and config.display
      and config.display.chat
      and config.display.chat.icons
    or {}

  local lines = {}
  for _, context in ipairs(chat.context_items) do
    if
      context
      and type(context.id) == 'string'
      and context.id ~= ''
      and not (context.opts and context.opts.visible == false)
    then
      local icon = ''
      if context.opts and context.opts.sync_all then
        icon = icons.buffer_sync_all or ''
      elseif context.opts and context.opts.sync_diff then
        icon = icons.buffer_sync_diff or ''
      end

      table.insert(lines, '> - ' .. icon .. context.id)
    end
  end

  return #lines > 0 and lines or nil
end

local function strip_generic_leading_context_block(lines)
  local start = 1
  while lines[start] and vim.trim(lines[start]) == '' do
    start = start + 1
  end

  if lines[start] ~= '> Context:' then
    return lines
  end

  local cursor = start + 1
  local saw_context_item = false
  while lines[cursor] and lines[cursor]:match('^>%s*%-%s+') do
    saw_context_item = true
    cursor = cursor + 1
  end

  if not saw_context_item then
    return lines
  end

  if lines[cursor] and lines[cursor] ~= '' then
    return lines
  end

  local remove_to = cursor - 1
  if lines[cursor] == '' then
    remove_to = cursor
  end

  local stripped = {}
  for i, line in ipairs(lines) do
    if i < start or i > remove_to then
      table.insert(stripped, line)
    end
  end

  return stripped
end

local function strip_leading_context_block(bufnr, lines)
  local context_lines = visible_context_lines(bufnr)
  if not context_lines then
    return strip_generic_leading_context_block(lines)
  end

  local start = 1
  while lines[start] and vim.trim(lines[start]) == '' do
    start = start + 1
  end

  if lines[start] ~= '> Context:' then
    return strip_generic_leading_context_block(lines)
  end

  local cursor = start + 1
  for _, context_line in ipairs(context_lines) do
    if lines[cursor] ~= context_line then
      return strip_generic_leading_context_block(lines)
    end

    cursor = cursor + 1
  end

  if
    lines[cursor]
    and lines[cursor] ~= ''
    and lines[cursor]:match('^>%s*%-%s+')
  then
    return strip_generic_leading_context_block(lines)
  end

  local remove_to = cursor - 1
  if lines[cursor] == '' then
    remove_to = cursor
  end

  local stripped = {}
  for i, line in ipairs(lines) do
    if i < start or i > remove_to then
      table.insert(stripped, line)
    end
  end

  return stripped
end

local function draft_has_user_content(prompt)
  if type(prompt) ~= 'string' or vim.trim(prompt) == '' then
    return false
  end

  local lines = strip_generic_leading_context_block(
    vim.split(prompt, '\n', { plain = true })
  )

  return vim.trim(table.concat(lines, '\n')) ~= ''
end

local function llm_role(bufnr)
  local config = cc_config()
  local role = config
      and config.interactions
      and config.interactions.chat
      and config.interactions.chat.roles
      and config.interactions.chat.roles.llm
    or nil

  if type(role) == 'function' then
    local chat = chat_for_buf(bufnr)
    local ok, resolved = pcall(role, chat and chat.adapter or {})
    if ok and type(resolved) == 'string' then
      return resolved
    end
    return nil
  end

  if type(role) == 'string' then
    return role
  end

  return nil
end

local function is_llm_header(bufnr, line)
  local role = llm_role(bufnr)
  if role_header_matches(line, role) then
    return true
  end

  return type(line) == 'string'
    and line:match('^##%s+CodeCompanion%s*%(') ~= nil
end

local function active_prompt(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  if not is_codecompanion_buf(bufnr) then
    return nil
  end

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local last_role_header = nil

  for i, line in ipairs(lines) do
    if is_header(line) then
      if is_user_header(line) then
        last_role_header = { kind = 'user', line = i }
      elseif is_llm_header(bufnr, line) then
        last_role_header = { kind = 'llm', line = i }
      end
    end
  end

  if not last_role_header or last_role_header.kind ~= 'user' then
    return nil
  end

  return {
    header = last_role_header.line,
    lines = strip_leading_context_block(
      bufnr,
      vim.list_slice(lines, last_role_header.line + 1)
    ),
  }
end

local function draft_marks(active_bufnr)
  local marks = {}

  for _, bufnr in ipairs(open_codecompanion_buffers()) do
    local mark = bufnr == active_bufnr and 'this' or 'open'

    mark_path(marks, primary_path(bufnr), mark)
    for _, path in ipairs(delete_paths(bufnr)) do
      mark_path(marks, path, mark)
    end
  end

  return marks
end

local function prompt_text(bufnr)
  local prompt = active_prompt(bufnr)
  if not prompt then
    return nil
  end

  return table.concat(prompt.lines, '\n')
end

local function stop_timer(bufnr)
  local timer = timers[bufnr]
  if timer then
    timer:stop()
    timer:close()
    timers[bufnr] = nil
  end
end

local function save_open_drafts()
  for _, bufnr in ipairs(open_codecompanion_buffers()) do
    stop_timer(bufnr)
    M.save(bufnr)
  end
end

local function is_submitted_prompt(bufnr, prompt)
  local submitted_header =
    get_buf_var(bufnr, 'lpke_cc_draft_submitted_header', nil)
  local submitted_prompt =
    get_buf_var(bufnr, 'lpke_cc_draft_submitted_prompt', nil)

  return submitted_header == prompt.header
    and type(submitted_prompt) == 'string'
    and submitted_prompt == table.concat(prompt.lines, '\n')
end

local function mark_submitted_prompt(bufnr)
  local prompt = active_prompt(bufnr)
  if not prompt then
    return
  end

  set_buf_var(bufnr, 'lpke_cc_draft_submitted_header', prompt.header)
  set_buf_var(
    bufnr,
    'lpke_cc_draft_submitted_prompt',
    table.concat(prompt.lines, '\n')
  )
end

local function clear_submitted_prompt(bufnr)
  del_buf_var(bufnr, 'lpke_cc_draft_submitted_header')
  del_buf_var(bufnr, 'lpke_cc_draft_submitted_prompt')
end

local function clear_live_path(bufnr, path)
  local primary = primary_path(bufnr)
  local primary_deleted = primary == path

  if primary_deleted then
    mark_submitted_prompt(bufnr)
    del_buf_var(bufnr, 'lpke_cc_draft_path')
    del_buf_var(bufnr, 'lpke_cc_draft_cwd')
  end

  set_or_del_list_var(
    bufnr,
    'lpke_cc_draft_delete_paths',
    remove_path(delete_paths(bufnr), path)
  )
  set_or_del_list_var(
    bufnr,
    'lpke_cc_draft_restored_paths',
    remove_path(restored_paths(bufnr), path)
  )

  return primary_deleted
end

local function clear_live_paths(path)
  for _, bufnr in ipairs(open_codecompanion_buffers()) do
    stop_timer(bufnr)
    clear_live_path(bufnr, path)
  end
end

function M.save(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end
  if not api.nvim_buf_is_valid(bufnr) then
    stop_timer(bufnr)
    return false
  end

  local prompt = active_prompt(bufnr)
  if not prompt then
    return false
  end

  if is_submitted_prompt(bufnr, prompt) then
    return false
  end

  local prompt_content = table.concat(prompt.lines, '\n')
  local path = primary_path(bufnr)
  if not draft_has_user_content(prompt_content) then
    if path and not path_in(restored_paths(bufnr), path) then
      delete_file(path)
    end
    clear_paths(bufnr)
    return false
  end

  if not path then
    path = draft_path()
    set_primary_path(bufnr, path)
    add_delete_path(bufnr, path)
    set_buf_var(bufnr, 'lpke_cc_draft_cwd', cwd())
  end
  clear_submitted_prompt(bufnr)

  local ok = atomic_write(path, {
    prompt = prompt_content,
    cwd = draft_cwd(bufnr, path),
    timestamp = os.time(),
  })

  if ok then
    add_delete_path(bufnr, path)
  end

  return ok
end

function M.schedule_save(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end

  stop_timer(bufnr)
  local timer = vim.uv.new_timer()
  timers[bufnr] = timer
  timer:start(DEBOUNCE_MS, 0, function()
    vim.schedule(function()
      stop_timer(bufnr)
      M.save(bufnr)
    end)
  end)
end

function M.delete_for_buffer(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end

  stop_timer(bufnr)
  mark_submitted_prompt(bufnr)

  for _, path in ipairs(delete_paths(bufnr)) do
    delete_file(path)
  end

  local path = primary_path(bufnr)
  if path then
    delete_file(path)
  end

  clear_paths(bufnr)
end

function M.attach(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end

  local group = api.nvim_create_augroup('LpkeCodeCompanionDrafts:' .. bufnr, {
    clear = true,
  })

  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      M.schedule_save(bufnr)
    end,
  })

  api.nvim_create_autocmd({ 'InsertLeave', 'BufLeave', 'BufHidden' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      stop_timer(bufnr)
      M.save(bufnr)
    end,
  })

  api.nvim_create_autocmd({ 'BufUnload', 'BufDelete' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      stop_timer(bufnr)
      M.save(bufnr)
    end,
  })
end

function M.list_current_cwd()
  ensure_dir()

  local files = vim.fn.glob(DRAFT_DIR .. '/*.json', false, true)
  local current_cwd = cwd()
  local drafts = {}

  for _, path in ipairs(files) do
    local data = read_json(path)
    if
      data
      and data.cwd == current_cwd
      and type(data.prompt) == 'string'
      and draft_has_user_content(data.prompt)
      and type(data.timestamp) == 'number'
    then
      table.insert(drafts, {
        path = path,
        prompt = data.prompt,
        cwd = data.cwd,
        timestamp = data.timestamp,
      })
    end
  end

  table.sort(drafts, function(a, b)
    return a.timestamp > b.timestamp
  end)

  return drafts
end

local function active_bufnr(chat)
  if chat and chat.bufnr and api.nvim_buf_is_valid(chat.bufnr) then
    return chat.bufnr
  end

  local bufnr = api.nvim_get_current_buf()
  if is_codecompanion_buf(bufnr) then
    return bufnr
  end

  return nil
end

local function first_content_line(prompt)
  for _, line in ipairs(vim.split(prompt, '\n', { plain = true })) do
    local trimmed = vim.trim(line)
    if trimmed ~= '' then
      return trimmed
    end
  end

  return '[empty]'
end

local function preview(prompt)
  local line = first_content_line(prompt):gsub('%s+', ' ')
  if #line > 80 then
    return line:sub(1, 77) .. '...'
  end
  return line
end

local function format_item(item)
  local ok, utils = pcall(require, 'codecompanion.utils')
  local relative = ok and utils.make_relative(item.timestamp)
    or os.date('%Y-%m-%d %H:%M', item.timestamp)

  local prefix = item.mark and ('[' .. item.mark .. '] ') or ''
  return string.format('%s(%s) %s', prefix, relative, preview(item.prompt))
end

local function item_ordinal(item)
  return table.concat({
    item.mark or '',
    os.date('%Y-%m-%d %H:%M:%S', item.timestamp),
    preview(item.prompt),
    item.prompt,
  }, ' ')
end

local function preview_lines(item)
  if not item or type(item.prompt) ~= 'string' then
    return { 'Draft prompt is no longer available.' }
  end

  local lines = vim.split(item.prompt, '\n', { plain = true })
  while #lines > 0 and lines[1] == '' do
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines] == '' do
    table.remove(lines)
  end

  if #lines == 0 then
    return { '[empty]' }
  end

  return lines
end

local function draft_items(chat)
  save_open_drafts()

  local marks = draft_marks(active_bufnr(chat))
  local items = M.list_current_cwd()
  for _, item in ipairs(items) do
    item.mark = marks[item.path]
    item.display = format_item(item)
    item.ordinal = item_ordinal(item)
  end

  return items
end

local function selected_items(telescope, prompt_bufnr)
  local picker = telescope.action_state.get_current_picker(prompt_bufnr)
  local selections = picker and picker:get_multi_selection() or {}

  if #selections == 0 then
    local selection = telescope.action_state.get_selected_entry()
    if selection then
      selections = { selection }
    end
  end

  local items = {}
  local seen = {}
  for _, selection in ipairs(selections) do
    local item = selection.value
    if item and item.path and not seen[item.path] then
      seen[item.path] = true
      table.insert(items, item)
    end
  end

  return items
end

local function refresh_picker(telescope, prompt_bufnr, chat, make_finder)
  local picker = telescope.action_state.get_current_picker(prompt_bufnr)
  if not picker then
    return
  end

  picker:refresh(make_finder(draft_items(chat)), {
    reset_prompt = false,
  })
end

local function delete_selected(telescope, prompt_bufnr, chat, make_finder)
  local items = selected_items(telescope, prompt_bufnr)
  if #items == 0 then
    return
  end

  for _, item in ipairs(items) do
    delete_file(item.path)
    clear_live_paths(item.path)
  end

  refresh_picker(telescope, prompt_bufnr, chat, make_finder)
end

local function append_prompt(chat, item)
  if not chat or not chat.bufnr or not api.nvim_buf_is_valid(chat.bufnr) then
    notify('No current chat for draft restore', vim.log.levels.WARN)
    return
  end

  if chat.current_request then
    notify(
      'Cannot restore a draft while a request is running',
      vim.log.levels.WARN
    )
    return
  end

  local bufnr = chat.bufnr
  local current_prompt = prompt_text(bufnr)
  if current_prompt == nil then
    notify('Chat is not ready for draft restore', vim.log.levels.WARN)
    return
  end

  stop_timer(bufnr)
  M.save(bufnr)

  local existing_path = primary_path(bufnr)
  if vim.trim(current_prompt) == '' or not existing_path then
    set_primary_path(bufnr, item.path)
    set_buf_var(bufnr, 'lpke_cc_draft_cwd', item.cwd)
  end
  add_delete_path(bufnr, item.path)
  add_restored_path(bufnr, item.path)

  local lines = vim.split(item.prompt, '\n', { plain = true })
  while #lines > 0 and lines[1] == '' do
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines] == '' do
    table.remove(lines)
  end
  if #lines == 0 then
    return
  end

  local was_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true

  local line_count = api.nvim_buf_line_count(bufnr)
  local last_line = api.nvim_buf_get_lines(
    bufnr,
    line_count - 1,
    line_count,
    false
  )[1] or ''
  local insert = {}
  if vim.trim(current_prompt) ~= '' and last_line ~= '' then
    table.insert(insert, '')
  end
  vim.list_extend(insert, lines)

  local insert_ok =
    pcall(api.nvim_buf_set_lines, bufnr, line_count, line_count, false, insert)
  vim.bo[bufnr].modifiable = was_modifiable
  if not insert_ok then
    notify('Failed to restore draft prompt', vim.log.levels.ERROR)
    return
  end

  if chat.ui and chat.ui.is_visible and chat.ui:is_visible() then
    pcall(api.nvim_win_set_cursor, chat.ui.winnr, {
      api.nvim_buf_line_count(bufnr),
      0,
    })
  end

  M.schedule_save(bufnr)
end

function M.open_picker(chat)
  local drafts = draft_items(chat)
  if #drafts == 0 then
    notify('No draft prompts for current cwd')
    return
  end

  local ok, telescope = pcall(function()
    return {
      actions = require('telescope.actions'),
      action_state = require('telescope.actions.state'),
      conf = require('telescope.config').values,
      finders = require('telescope.finders'),
      pickers = require('telescope.pickers'),
      previewers = require('telescope.previewers'),
    }
  end)

  if not ok then
    notify('Telescope is not available for draft prompts', vim.log.levels.ERROR)
    return
  end

  local function make_finder(items)
    return telescope.finders.new_table({
      results = items,
      entry_maker = function(item)
        return {
          value = item,
          display = item.display,
          ordinal = item.ordinal,
          path = item.path,
        }
      end,
    })
  end

  telescope.pickers
    .new({}, {
      prompt_title = 'Draft Prompts',
      finder = make_finder(drafts),
      sorter = telescope.conf.generic_sorter({}),
      previewer = telescope.previewers.new_buffer_previewer({
        title = 'Draft Prompt',
        define_preview = function(self, entry)
          local lines = preview_lines(entry and entry.value)
          vim.bo[self.state.bufnr].filetype = 'markdown'
          api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        telescope.actions.select_default:replace(function()
          local selection = telescope.action_state.get_selected_entry()
          telescope.actions.close(prompt_bufnr)
          if selection then
            append_prompt(chat, selection.value)
          end
        end)

        map('n', 'dD', function()
          delete_selected(telescope, prompt_bufnr, chat, make_finder)
        end)

        return true
      end,
    })
    :find()
end

function M.setup()
  local group = api.nvim_create_augroup('LpkeCodeCompanionDrafts', {
    clear = true,
  })

  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'CodeCompanionChatCreated',
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if bufnr then
        M.attach(bufnr)
      end
    end,
  })

  api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'codecompanion',
    callback = function(args)
      M.attach(args.buf)
    end,
  })

  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'CodeCompanionChatClosed',
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if bufnr then
        stop_timer(bufnr)
        M.save(bufnr)
      end
    end,
  })

  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'CodeCompanionChatSubmitted',
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if bufnr then
        vim.schedule(function()
          M.delete_for_buffer(bufnr)
        end)
      end
    end,
  })

  api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      for _, bufnr in ipairs(open_codecompanion_buffers()) do
        if api.nvim_buf_is_valid(bufnr) then
          stop_timer(bufnr)
          M.save(bufnr)
        end
      end
    end,
  })

  for _, bufnr in ipairs(open_codecompanion_buffers()) do
    if api.nvim_buf_is_valid(bufnr) then
      M.attach(bufnr)
    end
  end
end

return M
