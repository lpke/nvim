local M = {}
local state_view = require('lpke.plugins.git.helpers.state_view')

local function set_context(view, spec)
  if not view or not view.tabpage then
    error('Git review could not open ' .. tostring(spec.mode))
  end
  if spec.title ~= nil then
    assert(type(spec.title) == 'string', 'Git review title must be text')
    vim.t[view.tabpage].lpke_review_title = spec.title
  end
  local root = view.adapter.ctx.toplevel
  -- Structured command arguments preserve whitespace/control bytes. tcd only
  -- affects this tab; lcd also overrides inherited window-local directories.
  local function cwd()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(view.tabpage)) do
      vim.api.nvim_win_call(win, function()
        vim.api.nvim_cmd(
          { cmd = 'lcd', args = { root }, mods = { noautocmd = true } },
          {}
        )
      end)
    end
  end
  vim.api.nvim_win_call(vim.api.nvim_tabpage_get_win(view.tabpage), function()
    vim.api.nvim_cmd(
      { cmd = 'tcd', args = { root }, mods = { noautocmd = true } },
      {}
    )
  end)
  cwd()
  view.emitter:on('file_open_post', cwd)
end

function M.open(specs)
  local views = {}
  for _, spec in ipairs(specs) do
    local view
    if spec.mode == 'stash' then
      view = require('lpke.plugins.git.helpers.stash_view').open(spec)
    elseif spec.state then
      view = state_view.open(spec)
    elseif spec.mode == 'history' then
      local root = spec.repo_b64 and vim.base64.decode(spec.repo_b64)
        or vim.uv.cwd()
      local adapter = state_view.create_adapter(root)
      local argo = require('diffview.arg_parser').parse(spec.args or {})
      -- Startup reviews must retain their validated scope. Native interactive
      -- history keeps its own defaults, including its ordinary entry limit.
      argo.flags['max-count'] = { 'false' }
      argo.flags.n = nil
      argo.flags['diff-merges'] = { 'first-parent' }
      local paths = state_view.literal_paths(spec, argo.args)
      local options = adapter:file_history_options(nil, paths, argo)
      if options then
        view =
          require('diffview.scene.views.file_history.file_history_view').FileHistoryView({
            adapter = adapter,
            log_options = options,
          })
        if view:is_valid() then
          require('lpke.plugins.git.helpers.history_view').configure(view, spec)
          require('diffview.lib').add_view(view)
          view:open()
        end
      end
    else
      -- The state helper also supplies literal path parsing for legacy diffs.
      view = state_view.open(spec)
    end
    set_context(view, spec)
    views[#views + 1] = view
  end
  return views
end

return M
