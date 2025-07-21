local helpers = require('lpke.core.helpers')

-- get all active buffers (in use/visible)
function Lpke_get_active_bufs()
  local active_bufs = {}
  -- save all active bufs by iterating over all windows in each tab
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      local buf = vim.api.nvim_win_get_buf(win)
      active_bufs[buf] = true
    end
  end
  return active_bufs
end

-- print IDs for active tab/buffer/window
function Lpke_active()
  print(
    'Tab:'
      .. vim.api.nvim_get_current_tabpage()
      .. ', Buf:'
      .. vim.api.nvim_get_current_buf()
      .. ', Win:'
      .. vim.api.nvim_get_current_win()
      .. ', Buf name: '
      .. helpers.get_buf_name(0)
  )
end

function Lpke_buf_details(bufnr)
  local B = {}
  B.buf_name = helpers.get_buf_name(bufnr)
  B.file_type = helpers.get_file_type(bufnr)
  B.normal_buffer = vim.bo.buftype == ''
  B.oil_buffer = B.file_type == 'oil'
  B.codecompanion_buffer = B.file_type == 'codecompanion'
  B.oil_trash = not not string.match(B.buf_name, '^oil%-trash://')
  B.git_buffer_type = Lpke_git_buf(bufnr) or false
  return B
end
