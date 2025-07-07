local builtin = require('telescope.builtin')
local helpers = require('lpke.core.helpers')

local M = {}

-- workaround since breaking change where this can't be accessed with:
-- require('auto-session.session-lens.actions').delete_session()
function M.delete_session(bufnr)
  local auto_session = require('auto-session')
  local action_state = require('telescope.actions.state')
  local current_picker = action_state.get_current_picker(bufnr)
  current_picker:delete_selection(function(selection)
    if selection then
      auto_session.DeleteSessionFile(selection.path, selection.display())
    end
  end)
end

-- custom mapping functions
function M.remove_selected_from_qflist(bufnr)
  local qflist = vim.fn.getqflist()
  helpers.telescope_sel_foreach(bufnr, function(sel)
    for i, item in ipairs(qflist) do
      if item.bufnr == sel.bufnr and item.lnum == sel.lnum then
        table.remove(qflist, i)
        break
      end
    end
  end)
  vim.fn.setqflist(qflist)
  helpers.refresh_picker(bufnr)
  builtin.quickfix()
end

function M.force_delete_selected_bufs(bufnr)
  helpers.telescope_sel_foreach(bufnr, function(sel)
    vim.api.nvim_buf_delete(sel.bufnr, { force = true })
  end)
  builtin.buffers()
end

function M.remove_selected_from_harpoon(bufnr)
  helpers.telescope_sel_foreach(bufnr, function(sel)
    local filename = sel.value.filename and sel.value.filename or sel.filename
    require('harpoon.mark').rm_file(filename)
  end)
  vim.cmd('Telescope harpoon marks')
  pcall(function()
    require('lualine').refresh()
  end)
end

function M.remove_selected_from_codecompanion(bufnr)
  local cc_history = require('codecompanion').extensions.history
  helpers.telescope_sel_foreach(bufnr, function(sel)
    local save_id = sel.save_id
    cc_history.delete_chat(save_id)
  end)
  vim.cmd('CodeCompanionHistory')
  pcall(function()
    require('lualine').refresh()
  end)
end

return M
