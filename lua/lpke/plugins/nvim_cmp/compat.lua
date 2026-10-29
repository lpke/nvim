local M = {}

-- The pinned nvim-cmp still uses legacy UTF overloads and stylize_markdown.
-- Keep the replacements local to its position helpers and documentation view.
local function setup_positions()
  local position = require('cmp.types.lsp').Position

  position.to_utf8 = function(text, pos, from_encoding)
    from_encoding = from_encoding or 'utf-16'
    if
      from_encoding == 'utf-8'
      or pos.character < 0
      or (text == '' and pos.character ~= 0)
    then
      return pos
    end
    local ok, index =
      pcall(vim.str_byteindex, text, from_encoding, pos.character, true)
    if not ok then
      return pos
    end
    return { line = pos.line, character = index }
  end

  local function to_encoding(text, pos, from_encoding, target)
    from_encoding = from_encoding or 'utf-16'
    if from_encoding == target then
      return pos
    end
    local utf8 = position.to_utf8(text, pos, from_encoding)
    -- Match cmp's fallback for positions inside a multibyte character.
    for index = utf8.character, 0, -1 do
      local ok, converted = pcall(vim.str_utfindex, text, target, index, true)
      if ok then
        return { line = utf8.line, character = converted }
      end
    end
    return pos
  end

  position.to_utf16 = function(text, pos, from_encoding)
    return to_encoding(text, pos, from_encoding, 'utf-16')
  end
  position.to_utf32 = function(text, pos, from_encoding)
    return to_encoding(text, pos, from_encoding, 'utf-32')
  end
end

local function render_documents(buf, documents, width)
  -- Use the same normalization and Treesitter rendering as native LSP floats.
  local lines = vim.lsp.util._normalize_markdown(documents, { width = width })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].syntax = ''
  if not pcall(vim.treesitter.start, buf, 'markdown') then
    vim.bo[buf].syntax = 'markdown'
  end
end

local function setup_docs()
  local docs = require('cmp.view.docs_view')
  local config = require('cmp.config')
  local window = require('cmp.utils.window')
  local open = docs.open

  docs.open = function(self, entry, view, bottom_up)
    local documentation = config.get().window.documentation
    if
      documentation
      and entry
      and view
      and (not self.entry or entry.id ~= self.entry.id)
    then
      local documents = entry:get_documentation()
      if #documents == 0 then
        return self:close()
      end
      local border = window.get_border_info({ style = documentation })
      local available_width =
        math.max(vim.o.columns - (view.col + view.width) - 1, view.col - 1)
      if documentation.max_width > 0 then
        available_width = math.min(available_width, documentation.max_width)
      end
      local width = vim.lsp.util._make_floating_popup_size(documents, {
        max_width = math.max(1, available_width - border.horiz),
      })
      render_documents(self.window:get_buffer(), documents, width)
      -- The original method keeps all cmp positioning, sizing, and scrolling.
      -- Mark this entry rendered so it skips the deprecated renderer.
      self.entry = entry
    end

    open(self, entry, view, bottom_up)

    if documentation and self:visible() then
      -- Native LSP floats also shrink after Treesitter conceals fence lines.
      local win = self.window.win
      local height = vim.api.nvim_win_get_height(win)
      local text_height =
        vim.api.nvim_win_text_height(win, { max_height = height }).all
      if text_height > 0 and text_height < height then
        self.window.style.height = text_height
        self.window:open(self.window.style)
      end
    end
  end
end

function M.setup()
  if M.applied then
    return
  end
  setup_positions()
  setup_docs()
  M.applied = true
end

return M
