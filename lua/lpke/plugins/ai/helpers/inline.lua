local M = {}

local function patch_http()
  local http = require('codecompanion.interactions.inline.adapters.http')
  if http._lpke_selection_guard then
    return
  end
  http._lpke_selection_guard = true
  local create = http.new
  http.new = function(args)
    local request = create(args)
    local selection = args.inline._lpke_inline_selection
    if not selection then
      return request
    end
    request.edited = selection.text
    local apply = request.apply_edits
    function request:apply_edits(calls)
      local results = {}
      for _, call in ipairs(calls) do
        local before = self.edited
        local result = apply(self, { call })[1]
        if not result.error then
          local _, err =
            selection:assemble(self.edited, self.inline.target.lines)
          if err then
            self.edited = before
            result.error = err
          end
        end
        results[#results + 1] = result
      end
      return results
    end
    function request:get_new_content()
      return assert(selection:assemble(self.edited, self.inline.target.lines))
    end
    return request
  end
end

local function patch_acp()
  local acp = require('codecompanion.interactions.inline.adapters.acp')
  if acp._lpke_selection_guard then
    return
  end
  acp._lpke_selection_guard = true
  local keep = acp.keep_editable_changes
  function acp:keep_editable_changes(lines)
    local result = keep(self, lines)
    local selection = self.inline._lpke_inline_selection
    if
      selection
      and not selection:contains_changes(result, self.inline.target.lines)
    then
      require('codecompanion.utils.log'):warn(
        '[Inline] Ignored changes outside the visual selection'
      )
      return vim.deepcopy(self.inline.target.lines)
    end
    return result
  end
end

function M.open(opts)
  opts = opts or {}
  local selection
  if opts.visual then
    local err
    selection, err =
      require('lpke.plugins.ai.helpers.inline_selection').capture()
    if not selection then
      return vim.notify(err, vim.log.levels.WARN, { title = 'CodeCompanion' })
    end
  end
  local context = require('codecompanion.utils.context').get(
    vim.api.nvim_get_current_buf(),
    opts.visual and { range = 1 } or nil
  )
  if selection then
    selection:prepare(vim.api.nvim_buf_get_lines(context.bufnr, 0, -1, false))
    context.is_visual = true
    context.is_normal = false
    context.mode = selection.mode
    context.lines = vim.split(selection.text, '\n', { plain = true })
    context.code = selection.text
    context.start_line = selection.parts[1].row
    context.start_col = selection.parts[1].first + 1
    context.end_line = selection.parts[#selection.parts].row
    context.end_col = selection.parts[#selection.parts].last
    vim.cmd('normal! ' .. vim.keycode('<Esc>'))
  end
  patch_http()
  patch_acp()
  local inline = require('codecompanion.interactions.inline').new({
    buffer_context = context,
  })
  if not inline then
    return
  end
  inline._lpke_inline_selection = selection
  function inline:get_target()
    local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
    local whole = { first = 1, last = #lines }
    if selection then
      selection:prepare(lines)
    end
    return {
      lines = lines,
      context = whole,
      editable = selection and {
        first = selection.parts[1].row,
        last = selection.parts[#selection.parts].row,
      } or whole,
    }
  end
  local format = inline.format_target
  function inline:format_target(target)
    if not selection then
      return format(self, target)
    end
    -- Ask the native formatter for one complete source block, then replace its
    -- whole-buffer permission with the exact selection contract.
    local content = format(self, {
      lines = target.lines,
      context = target.context,
      editable = target.context,
    })
    local permission = '\n\nYou can edit any of this code.'
    if content:sub(-#permission) == permission then
      content = content:sub(1, -#permission - 1)
    end
    return content .. '\n\n' .. selection:describe()
  end
  require('codecompanion.interactions.inline.ui').open_input(inline, {
    on_submit = function(prompt)
      inline:prompt(prompt)
    end,
  })
  return inline
end

return M
