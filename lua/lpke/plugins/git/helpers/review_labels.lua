local M = {}

-- Cache filename ambiguity per selection/refresh, never per statusline frame.
function M.configure(view)
  local function invalidate()
    view._lpke_review_names = nil
  end
  view.emitter:on('file_open_post', invalidate)
  view.emitter:on('files_updated', invalidate)
end

local function basename(path)
  return path:match('[^/]+$') or path
end

local function display_path(view, path)
  local history = view.panel.entries
  local count = history and #history
  if not view._lpke_review_names or view._lpke_review_name_count ~= count then
    local names = {}
    local function add(value)
      if value then
        local name = basename(value)
        if names[name] == nil then
          names[name] = value
        elseif names[name] ~= value then
          names[name] = false
        end
      end
    end
    local function entry(value)
      add(value.path)
      add(value.oldpath)
    end
    if history then
      for _, commit in ipairs(history) do
        for _, file in ipairs(commit.files) do
          entry(file)
        end
      end
    elseif view.files then
      for _, file in view.files:iter() do
        entry(file)
      end
    end
    view._lpke_review_names = names
    view._lpke_review_name_count = count
  end
  local name = basename(path)
  return view._lpke_review_names[name] == false and path or name
end

function M.current()
  local title = vim.t.lpke_review_title
  local lib = package.loaded['diffview.lib']
  if type(title) ~= 'string' or title == '' or not lib then
    return
  end
  local view = lib.get_current_view()
  if not view or not view.cur_layout then
    return
  end
  local winid, bufnr =
    vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  for _, side in ipairs({ 'a', 'b', 'c', 'd' }) do
    local win = view.cur_layout[side]
    local file = win and win.file
    if
      win
      and win.id == winid
      and file
      and (file.bufnr == bufnr or win:is_nulled())
    then
      local entry = view.cur_entry
      if not entry or view.nulled then
        return title
      end
      -- Missing/binary sides can share Diffview's null buffer. The selected
      -- entry and window still identify the file and comparison side exactly.
      local path = side == 'a' and entry.oldpath or entry.path
      local role = ({ a = 'BEFORE', b = 'AFTER' })[side] or 'FILE'
      if entry.kind == 'conflicting' then
        role = ({ a = 'OURS', b = 'RESULT', c = 'THEIRS', d = 'BASE' })[side]
      elseif side == 'b' and view.adapter._lpke_readonly_label == 'Stash' then
        role = entry.kind == 'staged' and 'AFTER (INDEX)'
          or entry.status == '?' and 'AFTER (UNTRACKED)'
          or 'AFTER (WORKTREE)'
      end
      return role .. ': ' .. display_path(view, path) .. ' | ' .. title
    end
  end
end

return M
