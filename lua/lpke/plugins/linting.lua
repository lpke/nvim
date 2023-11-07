local function config()
  local lint = require('lint')
  local helpers = require('lpke.core.helpers')

  lint.linters_by_ft = {
    javascript = { 'eslint_d' },
    typescript = { 'eslint_d' },
    javascriptreact = { 'eslint_d' },
    typescriptreact = { 'eslint_d' },
    python = { 'pylint' },
  }

  local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
    group = lint_augroup,
    callback = function()
      lint.try_lint()
    end,
  })

  -- stylua: ignore start
  -- keymaps
  helpers.keymap_set_multi({
    {'nv', '<leader>L', function() lint.try_lint() end, { desc = 'Trigger linting for current file' }},
  })
end
-- stylua: ignore end

return {
  enabled = false, -- temporary until find a way to toggle
  'mfussenegger/nvim-lint',
  lazy = true,
  event = { 'BufReadPre', 'BufNewFile' },
  config = config,
}
