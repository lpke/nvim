local M = {}
local api = vim.api
local ns = api.nvim_create_namespace('LpkeChatHints')

-- Keep the text readable without highlighting, and use the theme's info
-- accent for keys. Row numbers keep transcript content out of the hint styling.
function M.append(lines, rows)
  local positions = {}
  for _, items in ipairs(rows) do
    local parts = {}
    for _, item in ipairs(items) do
      parts[#parts + 1] = ('[%s] %s'):format(item[1], item[2])
    end
    positions[#positions + 1] = #lines
    lines[#lines + 1] = table.concat(parts, '   ')
  end
  return positions
end

function M.apply(bufnr, rows)
  api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, row in ipairs(rows or {}) do
    local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
      end_col = #line,
      hl_group = 'Comment',
      priority = 200,
    })
    local from = 1
    while true do
      local first, last = line:find('%b[]', from)
      if not first then
        break
      end
      api.nvim_buf_set_extmark(bufnr, ns, row, first, {
        end_col = last - 1,
        hl_group = 'DiagnosticInfo',
        priority = 210,
      })
      from = last + 1
    end
  end
end

return M
