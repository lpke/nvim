local builtin = require('telescope.builtin')

local M = {}

-- refresh a telescope picker and optionally remember selection location
function M.refresh_picker(bufnr, remember, selection_defer_time)
  selection_defer_time = selection_defer_time or 5
  if remember == nil then
    remember = true
  end
  local ok, result = pcall(function()
    local actions_state = require('telescope.actions.state')
    local picker = actions_state.get_current_picker(bufnr)
    local index = picker._selection_row
    picker:refresh()
    if remember then
      vim.defer_fn(function()
        picker:set_selection(index)
      end, selection_defer_time)
    end
  end)

  if not ok then
    vim.notify('Error refreshing picker: ' .. result, vim.log.levels.ERROR)
  end
end

-- iterate over selection/s in a telescope picker
function M.telescope_sel_foreach(bufnr, func)
  local actions_state = require('telescope.actions.state')
  local actions_utils = require('telescope.actions.utils')

  local selections = {}
  actions_utils.map_selections(bufnr, function(entry)
    table.insert(selections, entry)
  end)

  if #selections == 0 then
    local selection = actions_state.get_selected_entry(bufnr)
    func(selection)
  else
    for _, v in ipairs(selections) do
      func(v)
    end
  end
end

-- workaround since breaking change where this can't be accessed with:
-- require('auto-session.session-lens.actions').delete_session()
function M.delete_session(bufnr)
  local auto_session = require('lpke.plugins.auto_session')
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
  M.telescope_sel_foreach(bufnr, function(sel)
    for i, item in ipairs(qflist) do
      if item.bufnr == sel.bufnr and item.lnum == sel.lnum then
        table.remove(qflist, i)
        break
      end
    end
  end)
  vim.fn.setqflist(qflist)
  M.refresh_picker(bufnr)
  builtin.quickfix()
end

function M.force_delete_selected_bufs(bufnr)
  M.telescope_sel_foreach(bufnr, function(sel)
    vim.api.nvim_buf_delete(sel.bufnr, { force = true })
  end)
  builtin.buffers()
end

function M.remove_selected_from_harpoon(bufnr)
  M.telescope_sel_foreach(bufnr, function(sel)
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
  M.telescope_sel_foreach(bufnr, function(sel)
    local save_id = sel.save_id
    cc_history.delete_chat(save_id)
  end)
  vim.cmd('CodeCompanionHistory')
  pcall(function()
    require('lualine').refresh()
  end)
end

return M
