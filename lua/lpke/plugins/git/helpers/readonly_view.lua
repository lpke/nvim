local M = {}

-- Immutable review adapters can be shared by child DiffViews. Guard writes at
-- the adapter boundary as well as the UI, including direct actions API calls.
function M.configure(view, label)
  if view._lpke_readonly then
    return
  end
  view._lpke_readonly = true
  local adapter = view.adapter
  local async = require('diffview.async')
  local function readonly()
    vim.notify(label .. ' review is read-only', vim.log.levels.INFO)
    return false
  end
  adapter._lpke_readonly_label = label
  adapter.add_files = readonly
  adapter.reset_files = readonly
  adapter.stage_index_file = readonly
  adapter.file_restore = async.wrap(function(_, _, _, _, callback)
    readonly()
    callback(false)
  end)
  for _, action in ipairs({
    'restore_entry',
    'toggle_stage_entry',
    'stage_all',
    'unstage_all',
  }) do
    view.emitter:on(action, function(event)
      event:stop_propagation()
      readonly()
    end)
  end
  local function protect()
    local helpers = require('lpke.core.helpers')
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(view.tabpage)) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      if ft == 'DiffviewFiles' or ft == 'DiffviewFileHistory' then
        for _, key in ipairs({ '-', 's', 'I', 'S', 'U', 'X', 'cc' }) do
          helpers.keymap_set({
            'n',
            key,
            readonly,
            { buf = buf, desc = label .. ' review is read-only' },
          })
        end
      elseif ft ~= 'DiffviewFileHistoryOptions' then
        vim.bo[buf].readonly = true
        vim.bo[buf].modifiable = false
      end
    end
  end
  view.emitter:on('file_open_post', protect)
  view.emitter:on('files_updated', protect)
end

DiffviewGlobal.emitter:on('view_opened', function(_, view)
  local label = view.adapter and view.adapter._lpke_readonly_label
  if label then
    M.configure(view, label)
  end
end)

return M
