local M = {}

local function default_fold_text()
  local ok, text = pcall(vim.fn.foldtext)
  if ok and type(text) == 'string' and text ~= '' then
    return text
  end

  local line = vim.fn.getline(vim.v.foldstart)
  return line ~= '' and line or ''
end

function M.setup()
  local ok, folds = pcall(require, 'codecompanion.interactions.chat.ui.folds')
  if not ok or folds._lpke_fold_text_patched then
    return
  end

  local original_fold_text = folds.fold_text

  folds.fold_text = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local fold_start = vim.v.foldstart - 1
    local fold_data = folds.fold_summaries[bufnr]
      and folds.fold_summaries[bufnr][fold_start]

    if fold_data then
      return original_fold_text()
    end

    return default_fold_text()
  end

  folds._lpke_fold_text_patched = true
end

return M
