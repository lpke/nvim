---@return {}
function get_ng_status()
  local neogit = require('neogit')
  local status = neogit.status.instance()
  return status
end

---@return {}
function get_ng_ui()
  local status = get_ng_status()
  local ui = status.buffer.ui
  return ui
end

---@return {}
function get_ng_fold()
  local ui = get_ng_ui()
  local fold = ui:get_fold_under_cursor()
  return fold
end

-- Runs the native neogit `Toggle` action
function ng_native_toggle()
  local status = get_ng_status()
  local native_toggle_action = status:_action('n_toggle')
  native_toggle_action()
end

---@return { folded: boolean | nil, type: 'hunk' | 'file' | 'section' | nil }
function get_ng_pos()
  local fold = get_ng_fold()
  if not fold then
    vim.notify('get_ng_pos: no fold data available', vim.log.levels.WARN)
    return {
      folded = nil,
      type = nil,
    }
  end
  local folded = nil
  if type(fold.options.folded) == 'boolean' then
    folded = fold.options.folded
  end
  return {
    folded = folded,
    type = fold.options.hunk and 'hunk'
      or fold.options.filename and 'file'
      or fold.options.section and 'section'
      or nil,
  }
end

function ng_toggle_hunk() end

function ng_toggle_file() end

function ng_toggle_section() end

function ng_toggle() end
