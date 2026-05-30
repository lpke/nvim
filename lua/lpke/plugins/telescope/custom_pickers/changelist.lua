local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local make_entry = require('telescope.make_entry')
local config_values = require('telescope.config').values

local changelist = function(opts)
  opts = opts or {}

  local bufnr = vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local changes = vim.fn.getchangelist(bufnr)[1]
  local sorted_changes = {}

  for i = #changes, 1, -1 do
    local change = changes[i]
    if
      change.lnum > 0 and change.lnum <= vim.api.nvim_buf_line_count(bufnr)
    then
      change.bufnr = bufnr
      change.filename = filename
      change.text = vim.api.nvim_buf_get_lines(
        bufnr,
        change.lnum - 1,
        change.lnum,
        false
      )[1] or ''
      table.insert(sorted_changes, change)
    end
  end

  pickers
    .new(opts, {
      prompt_title = 'Changelist',
      finder = finders.new_table({
        results = sorted_changes,
        entry_maker = make_entry.gen_from_quickfix(opts),
      }),
      previewer = config_values.qflist_previewer(opts),
      sorter = config_values.generic_sorter(opts),
    })
    :find()
end

return changelist
