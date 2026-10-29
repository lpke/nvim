local M = {}
local api = vim.api
local previous = setmetatable({}, { __mode = 'k' })
local highlight = 'LpkeCodeCompanionReasoning'
local namespace = api.nvim_create_namespace('lpke-codecompanion-reasoning')

local function normalize_prefix(lines, write, target)
  local count = 0
  while count < write.content_start and lines[count + 1] == '' do
    count = count + 1
  end
  while count > target do
    table.remove(lines, 1)
    write.content_start = write.content_start - 1
    count = count - 1
  end
  while count < target do
    table.insert(lines, 1, '')
    write.content_start = write.content_start + 1
    count = count + 1
  end
end

local function format_prefix(self, lines, opts, write)
  local content_start = write.content_start
  if content_start == nil then
    return
  end

  -- Only generated prefix rows can be removed. The same headings in user or
  -- assistant content must remain untouched.
  for index = content_start, 1, -1 do
    if lines[index] == '### Reasoning' or lines[index] == '### Response' then
      table.remove(lines, index)
      write.content_start = write.content_start - 1
      if lines[index] == '' then
        table.remove(lines, index)
        write.content_start = write.content_start - 1
      end
    end
  end

  if not write.role_changed and content_start > 0 then
    local prior = previous[self]
    local changed_type = opts.type ~= nil
      and prior ~= nil
      and prior ~= self.state.block_type
    local blanks = prior == false and 0 or (changed_type and 2 or 1)
    normalize_prefix(lines, write, blanks)
  end

  local delta = write.content_start - content_start
  if write.fold_info then
    write.fold_info.start_offset = write.fold_info.start_offset + delta
    write.fold_info.end_offset = write.fold_info.end_offset + delta
  end
end

local function apply_highlight(bufnr, next_line, lines, content_start)
  if not next_line or not api.nvim_buf_is_valid(bufnr) then
    return
  end
  local first_row = next_line - #lines + content_start
  local existing = {}
  for _, mark in
    ipairs(
      api.nvim_buf_get_extmarks(
        bufnr,
        namespace,
        { first_row, 0 },
        { next_line - 1, -1 },
        {}
      )
    )
  do
    existing[mark[2]] = mark[1]
  end
  local written = api.nvim_buf_get_lines(bufnr, first_row, next_line, false)
  for index, text in ipairs(written) do
    if lines[content_start + index] ~= '' and text ~= '' then
      local row = first_row + index - 1
      api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
        id = existing[row],
        end_row = row,
        end_col = #text,
        hl_group = highlight,
        hl_mode = 'replace',
        priority = 210,
      })
    end
  end
end

function M.patch()
  require('lpke.core.helpers').set_hl(highlight, {
    fg = Lpke_theme_colors.muted,
    bold = true,
    italic = false,
    nocombine = true,
  })
  local Builder = require('codecompanion.interactions.chat.ui.builder')
  if Builder._lpke_render then
    return
  end
  local add_message, write_message = Builder.add_message, Builder._write
  Builder.add_message = function(self, ...)
    previous[self] = self.state.block_type or false
    return add_message(self, ...)
  end
  Builder._write = function(self, lines, opts, write)
    format_prefix(self, lines, opts, write)
    -- Preserve earlier chunks' trailing newlines. Prefix normalization alone
    -- controls spacing, and the native write still owns headers, icons/folds.
    write.trailing_blanks = nil
    local reasoning = self.state.block_type == 'reasoning'
    local next_line, icon_id = write_message(self, lines, opts, write)
    if reasoning and write.content_start ~= nil then
      apply_highlight(self.chat.bufnr, next_line, lines, write.content_start)
    end
    return next_line, icon_id
  end
  Builder._lpke_render = true
  api.nvim_create_autocmd('User', {
    pattern = 'CodeCompanionChatCleared',
    group = api.nvim_create_augroup(
      'LpkeCodeCompanionReasoningHighlights',
      { clear = true }
    ),
    callback = function(args)
      local bufnr = args.data and args.data.bufnr
      if bufnr and api.nvim_buf_is_valid(bufnr) then
        api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
      end
    end,
  })
end

return M
