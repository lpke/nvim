local helpers = require('lpke.core.helpers')

-- disable next line auto-comment
vim.cmd('autocmd FileType * set formatoptions-=cro')

-- toggle diagnostics when going enter/leave insert mode
Lpke_diagnostics_insert_disabled = nil
vim.api.nvim_create_autocmd('InsertEnter', {
  pattern = '*',
  callback = function()
    Lpke_diagnostics_insert_disabled = true
    Lpke_toggle_diagnostics(false)
  end,
})
vim.api.nvim_create_autocmd('InsertLeave', {
  pattern = '*',
  callback = function()
    if Lpke_diagnostics_insert_disabled then
      Lpke_toggle_diagnostics(Lpke_diagnostics_enabled_prev)
      Lpke_diagnostics_insert_disabled = false
    end
  end,
})

-- quickfix-specific keymaps
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'qf',
  callback = function(event)
    local qf_winid = vim.fn.win_getid()

    local function delete_qf_items(start_line, end_line)
      local qf_list = vim.fn.getqflist()
      -- Remove items in reverse order to maintain correct indices
      for i = end_line, start_line, -1 do
        table.remove(qf_list, i)
      end
      vim.fn.setqflist(qf_list, 'r')
      -- Keep cursor position, but ensure it's within bounds
      local new_line = math.min(start_line, #qf_list)
      if new_line > 0 then
        vim.fn.cursor(new_line, 1)
      end
    end

    -- stylua: ignore start
    helpers.keymap_set_multi({
      -- navigate while keeping focus inside qf window
      { 'n', 'o', function()
        local qf_list = vim.fn.getqflist()
        local current_line = vim.fn.line('.')
        local qf_item = qf_list[current_line]
        if qf_item and qf_item.valid == 1 then
          vim.cmd('cc ' .. current_line)
        end
        vim.fn.win_gotoid(qf_winid)
      end, { desc = 'Open quickfix item (stay in quickfix)', buffer = event.buf }, },
      { 'n', 'J', function()
        helpers.safe_call(function() vim.cmd('cnext') end, true)
        vim.fn.win_gotoid(qf_winid)
      end, { desc = 'Next quickfix item (stay in quickfix)', buffer = event.buf }, },
      { 'n', 'K', function()
        helpers.safe_call(function() vim.cmd('cprev') end, true)
        vim.fn.win_gotoid(qf_winid)
      end, { desc = 'Previous quickfix item (stay in quickfix)', buffer = event.buf, }, },
      -- delete quickfix items
      { 'n', 'dd', function()
        local line = vim.fn.line('.')
        delete_qf_items(line, line)
      end, { desc = 'Delete quickfix item under cursor', buffer = event.buf }, },
      { 'v', 'd', function()
        local start_line = vim.fn.line('v')
        local end_line = vim.fn.line('.')
        if start_line > end_line then
          start_line, end_line = end_line, start_line
        end
        delete_qf_items(start_line, end_line)
        helpers.safe_call(function() vim.cmd('normal! <Esc>') end, true)
      end, { desc = 'Delete visually selected quickfix items', buffer = event.buf }, },
    })
    -- stylua: ignore end
  end,
})

-- remember folds
vim.api.nvim_create_autocmd({ 'BufWinLeave' }, {
  pattern = { '*.*' },
  desc = 'Save view (folds) when closing file',
  command = 'mkview',
})
vim.api.nvim_create_autocmd({ 'BufWinEnter' }, {
  pattern = { '*.*' },
  desc = 'load view (folds) when opening file',
  command = 'silent! loadview',
})
