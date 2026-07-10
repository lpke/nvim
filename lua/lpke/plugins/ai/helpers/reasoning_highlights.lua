local M = {}

local api = vim.api
local highlight = 'LpkeCodeCompanionReasoning'
local namespace = api.nvim_create_namespace('lpke-codecompanion-reasoning')

local function leading_blanks(lines)
  local count = 0
  while lines[count + 1] == '' do
    count = count + 1
  end
  return count
end

local function apply_highlight(bufnr, next_line, info)
  if
    not next_line
    or not api.nvim_buf_is_valid(bufnr)
    or info.content_offset >= info.line_count
  then
    return
  end

  local end_row = next_line - 1
  local start_row = next_line - info.line_count + info.content_offset
  local end_text = api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1]
    or ''

  api.nvim_buf_set_extmark(bufnr, namespace, start_row, 0, {
    end_row = end_row,
    end_col = #end_text,
    hl_group = highlight,
    hl_mode = 'replace',
    priority = 210,
  })
end

local function patch_formatter()
  local formatter =
    require('codecompanion.interactions.chat.ui.formatters.reasoning')
  if formatter._lpke_highlight_reasoning then
    return
  end

  local original_format = formatter.format
  formatter.format = function(self, message, opts, state)
    local lines, fold_info = original_format(self, message, opts, state)
    opts._lpke_reasoning_highlight = {
      content_offset = leading_blanks(lines),
      line_count = #lines,
    }
    return lines, fold_info
  end
  formatter._lpke_highlight_reasoning = true
end

local function patch_builder()
  local builder = require('codecompanion.interactions.chat.ui.builder')
  if builder._lpke_highlight_reasoning then
    return
  end

  local original_add_message = builder.add_message
  builder.add_message = function(self, data, opts)
    opts = opts or {}
    local next_line, icon_id = original_add_message(self, data, opts)
    local info = opts._lpke_reasoning_highlight
    opts._lpke_reasoning_highlight = nil
    if info then
      apply_highlight(self.chat.bufnr, next_line, info)
    end
    return next_line, icon_id
  end
  builder._lpke_highlight_reasoning = true
end

local function setup_clear()
  vim.api.nvim_create_autocmd('User', {
    pattern = 'CodeCompanionChatCleared',
    group = vim.api.nvim_create_augroup(
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

function M.patch()
  require('lpke.core.helpers').set_hl(highlight, {
    fg = Lpke_theme_colors.muted,
    bold = true,
    italic = false,
    nocombine = true,
  })
  patch_formatter()
  patch_builder()
  setup_clear()
end

return M
