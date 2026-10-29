local M = {}
local api = vim.api

function M.read(chat)
  return table.concat(
    api.nvim_buf_get_lines(chat.bufnr, chat.header_line, -1, false),
    '\n'
  )
end

function M.has_prompt(chat)
  local ok, message = pcall(
    require('codecompanion.interactions.chat.parser').messages,
    chat,
    chat.header_line
  )
  return ok
    and message ~= nil
    and type(message.content) == 'string'
    and vim.trim(message.content) ~= ''
end

-- Remove only the rows rendered for this chat's visible context items.
-- Similar-looking blockquotes written by the user remain part of the prompt.
function M.strip_context(chat, lines)
  local icons = require('codecompanion.config').display.chat.icons
  local context = { '> Context:' }
  for _, item in ipairs(chat.context_items or {}) do
    if item and not (item.opts and item.opts.visible == false) then
      local icon = item.opts and item.opts.sync_all and icons.sync_all
        or item.opts and item.opts.sync_diff and icons.sync_diff
        or ''
      context[#context + 1] = '> - ' .. icon .. item.id
    end
  end
  if #context == 1 then
    return lines
  end

  local start = 1
  while lines[start] and vim.trim(lines[start]) == '' do
    start = start + 1
  end
  for i, line in ipairs(context) do
    if lines[start + i - 1] ~= line then
      return lines
    end
  end
  local finish = start + #context
  if lines[finish] == '' then
    finish = finish + 1
  end
  return vim.list_extend(
    vim.list_slice(lines, 1, start - 1),
    vim.list_slice(lines, finish)
  )
end

-- The native header position identifies the active user section, including
-- prompts containing Markdown headings, fenced code, or quoted role names.
function M.prompt(chat)
  if not chat or not api.nvim_buf_is_valid(chat.bufnr) then
    return nil
  end
  local header = chat.header_line
  if
    not header
    or header < 1
    or header > api.nvim_buf_line_count(chat.bufnr)
  then
    return nil
  end
  local config = require('codecompanion.config')
  local expected = '## ' .. config.interactions.chat.roles.user
  local line = api.nvim_buf_get_lines(chat.bufnr, header - 1, header, false)[1]
  if
    line ~= expected
    and not line:match(
      '^'
        .. vim.pesc(expected)
        .. '%s+'
        .. vim.pesc(config.display.chat.separator)
    )
  then
    return nil
  end
  return {
    header = header,
    lines = M.strip_context(
      chat,
      api.nvim_buf_get_lines(chat.bufnr, header, -1, false)
    ),
  }
end

function M.empty(chat)
  local prompt = M.prompt(chat)
  return prompt ~= nil and vim.trim(table.concat(prompt.lines, '\n')) == ''
end

return M
