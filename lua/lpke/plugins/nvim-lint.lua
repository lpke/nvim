Lpke_linting_enabled = true

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
  local function setup_lint_autocmds()
    vim.api.nvim_create_autocmd({
      'BufEnter',
      'BufWritePost',
      'InsertLeave',
      'FocusGained',
      'TextChanged',
    }, {
      group = lint_augroup,
      callback = function()
        vim.defer_fn(lint.try_lint, 100)
      end,
    })
  end

  local function clear_lint_autocmds()
    vim.api.nvim_clear_autocmds({ group = lint_augroup })
    vim.diagnostic.reset(nil) -- kills all diagnostics globally
    vim.cmd('LspRestart') -- restart LSP
  end

  function Lpke_toggle_linting()
    local enabled = Lpke_linting_enabled
    if enabled then
      clear_lint_autocmds()
      Lpke_linting_enabled = false
    else
      setup_lint_autocmds()
      lint.try_lint()
      Lpke_linting_enabled = true
    end
    pcall(function()
      require('lualine').refresh()
    end)
  end

  -- initialise linting (respect initial preference)
  if Lpke_linting_enabled then
    setup_lint_autocmds()
  end

  -- stylua: ignore start
  -- keymaps
  helpers.keymap_set_multi({
    {'nv', '<F2>t', Lpke_toggle_linting, { desc = 'Toggle linting globally' }},
    {'nv', '<leader>L', lint.try_lint, { desc = 'Trigger linting for current file' }},
  })
end
-- stylua: ignore end

return {
  'mfussenegger/nvim-lint',
  lazy = true,
  event = { 'BufReadPre', 'BufNewFile' },
  config = config,
}
