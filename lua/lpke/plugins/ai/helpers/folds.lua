local M = {}

function M.setup()
  local folds = require('codecompanion.interactions.chat.ui.folds')
  if folds._lpke_fold_text_patched then
    return
  end
  local original_fold_text = folds.fold_text
  folds.fold_text = function()
    local summaries = folds.fold_summaries[vim.api.nvim_get_current_buf()]
    if summaries and summaries[vim.v.foldstart - 1] then
      return original_fold_text()
    end
    return vim.fn.foldtext()
  end
  folds._lpke_fold_text_patched = true
end

return M
