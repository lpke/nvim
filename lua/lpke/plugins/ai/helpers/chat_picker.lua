local M = {}

local ai_config = require('lpke.plugins.ai.helpers.config')
local chat_fns = require('lpke.plugins.ai.helpers.chat_functions')

local actions
local action_state
local finders

local BLANK_DESC = '[No messages]'

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = 'CodeCompanion' })
end

local function normalize_space(value)
  value = tostring(value or ''):gsub('%s+', ' ')
  return vim.trim(value)
end

local function is_codecompanion_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local ok, filetype = pcall(function()
    return vim.bo[bufnr].filetype
  end)

  return ok and filetype == 'codecompanion'
end

local function registry_entries()
  local registry = require('codecompanion.interactions.shared.registry')
  local entries = vim.tbl_filter(function(entry)
    return entry.interaction == 'chat' and is_codecompanion_buffer(entry.bufnr)
  end, registry.list())

  table.sort(entries, function(a, b)
    return a.bufnr < b.bufnr
  end)

  return entries
end

local function chat_for_buf(bufnr)
  local ok, codecompanion = pcall(require, 'codecompanion')
  if not ok or type(codecompanion.buf_get_chat) ~= 'function' then
    return nil
  end

  return codecompanion.buf_get_chat(bufnr)
end

local function adapter_display(adapter)
  if not adapter then
    return 'Unknown'
  end

  local name = adapter.name
  if name then
    return ai_config.adapter_display_name(name)
  end

  return adapter.formatted_name or adapter.type or 'Unknown'
end

local function adapter_type(adapter)
  return string.upper(adapter and adapter.type or 'unknown')
end

local function chat_title(chat, entry, index)
  local title = chat.title
    or (chat.opts and chat.opts.title)
    or entry.description

  title = normalize_space(title)
  if title == '' or title == BLANK_DESC then
    title = normalize_space(entry.name)
  end
  if title == '' then
    title = string.format('Chat %d', index)
  end

  return title
end

local function chat_is_processing(chat)
  if not chat then
    return false
  end

  if chat.current_request then
    return true
  end

  local ok, spinner = pcall(require, 'lpke.plugins.ai.helpers.chat_spinner')
  local state = ok and spinner.buffers and spinner.buffers[chat.bufnr]
  return state and state.processing == true
end

local function display_line(item)
  return string.format(
    '%d%s %s / %s: %s',
    item.index,
    item.processing and '!' or ' ',
    item.adapter_type,
    item.adapter,
    item.title
  )
end

function M.build_entries()
  local items = {}

  for _, entry in ipairs(registry_entries()) do
    local chat = chat_for_buf(entry.bufnr)
    if chat then
      local index = #items + 1
      local item = {
        index = index,
        bufnr = entry.bufnr,
        chat = chat,
        registry_entry = entry,
        processing = chat_is_processing(chat),
        adapter = adapter_display(chat.adapter),
        adapter_type = adapter_type(chat.adapter),
        title = chat_title(chat, entry, index),
      }

      item.display = display_line(item)
      item.ordinal = table.concat({
        tostring(item.index),
        item.adapter_type,
        item.adapter,
        item.title,
      }, ' ')

      table.insert(items, item)
    end
  end

  return items
end

local function preview_lines(item)
  if
    not item
    or not item.bufnr
    or not vim.api.nvim_buf_is_valid(item.bufnr)
  then
    return { 'Chat buffer is no longer available.' }
  end

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, item.bufnr, 0, -1, false)
  if not ok or #lines == 0 then
    return { BLANK_DESC }
  end

  return lines
end

function M.open_selected(item)
  if not item or not item.bufnr then
    return
  end

  local function notify_opened()
    notify(string.format('Chat %d/%d', item.index, #M.build_entries()))
  end

  local entry =
    require('codecompanion.interactions.shared.registry').get(item.bufnr)
  if entry and type(entry.open) == 'function' then
    entry.open()
    notify_opened()
    return
  end

  local chat = chat_for_buf(item.bufnr)
  if not chat or not chat.ui then
    notify('Chat is no longer available', vim.log.levels.WARN)
    return
  end

  local active_chat = require('codecompanion').last_chat()
  if
    active_chat
    and active_chat ~= chat
    and active_chat.ui
    and active_chat.ui:is_visible()
  then
    active_chat.ui:hide()
  end

  chat.ui:open()
  notify_opened()
end

local function selected_items(prompt_bufnr)
  local picker = action_state.get_current_picker(prompt_bufnr)
  local selections = picker and picker:get_multi_selection() or {}

  if #selections == 0 then
    local selection = action_state.get_selected_entry()
    if selection then
      selections = { selection }
    end
  end

  local items = {}
  local seen = {}
  for _, selection in ipairs(selections) do
    local item = selection.value
    if item and item.bufnr and not seen[item.bufnr] then
      seen[item.bufnr] = true
      table.insert(items, item)
    end
  end

  return items
end

local function make_finder(items)
  return finders.new_table({
    results = items,
    entry_maker = function(item)
      return {
        value = item,
        display = item.display,
        ordinal = item.ordinal,
        bufnr = item.bufnr,
      }
    end,
  })
end

local function refresh_picker(prompt_bufnr)
  local picker = action_state.get_current_picker(prompt_bufnr)
  if not picker then
    return
  end

  local items = M.build_entries()
  picker:refresh(make_finder(items), {
    reset_prompt = false,
  })
end

local function delete_items(items)
  if #items == 0 then
    return
  end

  for _, item in ipairs(items) do
    local chat = chat_for_buf(item.bufnr)
    if chat then
      chat_fns.delete_current_chat(chat)
    end
  end
end

function M.delete_selected(prompt_bufnr)
  local items = selected_items(prompt_bufnr)
  delete_items(items)
  refresh_picker(prompt_bufnr)
end

function M.close_empty_chats(prompt_bufnr, current)
  require('lpke.plugins.ai.helpers.cleanup').close_empty_chats(current)
  refresh_picker(prompt_bufnr)
end

function M.open(opts)
  opts = opts or {}

  if vim.bo.filetype ~= 'codecompanion' then
    notify('Open chat picker from a CodeCompanion buffer', vim.log.levels.WARN)
    return
  end

  local items = M.build_entries()
  if #items == 0 then
    notify('No open chats')
    return
  end

  local source_chat = chat_for_buf(vim.api.nvim_get_current_buf())

  actions = require('telescope.actions')
  action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values
  finders = require('telescope.finders')
  local pickers = require('telescope.pickers')
  local previewers = require('telescope.previewers')

  pickers
    .new(opts, {
      prompt_title = 'CodeCompanion Chats',
      finder = make_finder(items),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = 'Chat Thread',
        define_preview = function(self, entry)
          local lines = preview_lines(entry and entry.value)
          vim.bo[self.state.bufnr].filetype = 'markdown'
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            M.open_selected(selection.value)
          end
        end)

        map('n', 'dD', function()
          M.delete_selected(prompt_bufnr)
        end)
        map('n', 'dX', function()
          M.close_empty_chats(prompt_bufnr, source_chat)
        end)

        return true
      end,
    })
    :find()
end

return M
