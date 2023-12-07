-- stylua: ignore start
local h = require('lpke.snippets.helpers')
---@diagnostic disable-next-line: unused-local
local ls, s, _s, sn, t, t_, i, f, d, rep, fmtc, fmta, fmt, sel, sel_q, sel_b, exp_conds =
  h.ls, h.s, h._s, h.sn, h.t, h.t_, h.i, h.f, h.d, h.rep, h.fmtc, h.fmta, h.fmt, h.sel, h.sel_q, h.sel_b, h.exp_conds
-- stylua: ignore end

local function get_opening_tag_name()
  -- Get the current line contents up to the cursor position
  local line = vim.api.nvim_get_current_line()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)[2]
  local line_to_cursor = line:sub(1, cursor_pos)

  -- Pattern match to find the tag. This regex captures the first word after '<'.
  local tag = line_to_cursor:match('<([%w_]+%.?[%w_]*)')
  return tag or ''
end

return { -- html
}
