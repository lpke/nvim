local function config()
  local conform = require('conform')
  local helpers = require('lpke.core.helpers')

  conform.setup({
    -- Formatters are installed by Mason (see `:Mason`)
    formatters_by_ft = {
      js = { 'prettier' },
      javascript = { 'prettier' },
      ts = { 'prettier' },
      typescript = { 'prettier' },
      jsx = { 'prettier' },
      javascriptreact = { 'prettier' },
      tsx = { 'prettier' },
      typescriptreact = { 'prettier' },
      svelte = { 'prettier' },
      css = { 'prettier' },
      html = { 'prettier' },
      json = { 'prettier' },
      jsonc = { 'prettier_jsonc' },
      yaml = { 'prettier' },
      markdown = { 'prettier' },
      graphql = { 'prettier' },
      lua = { 'stylua' },
      python = { 'isort', 'black' },
      sh = { 'shfmt' },
      bash = { 'shfmt' },
      zsh = { 'shfmt' },
      toml = { 'taplo' },
    },
    -- Default overrides (including config)
    formatters = {
      prettier_jsonc = {
        command = 'prettier',
        args = {
          '--config-precedence',
          'file-override',
          '--single-quote',
          '--tab-width',
          '2',
          '--trailing-comma',
          'none',
          '--parser',
          'json',
          '--stdin-filepath',
          '$FILENAME',
        },
        stdin = true,
      },
      prettier = {
        -- https://prettier.io/docs/cli
        -- https://prettier.io/docs/options
        prepend_args = {
          '--config-precedence',
          'file-override',
          '--single-quote',
          '--tab-width',
          '2',
        },
      },
      stylua = {
        -- https://github.com/johnnymorganz/stylua#configuration
        prepend_args = function(_self, _ctx)
          if
            helpers.find_file_upward({
              '.stylua.toml',
              'stylua.toml',
            })
          then
            return {}
          end
          return {
            '--indent-width',
            '2',
            '--indent-type',
            'spaces',
            '--column-width',
            '80',
            '--quote-style',
            'autoprefersingle',
          }
        end,
      },
      taplo = {
        -- https://taplo.tamasfe.dev/cli/usage/formatting.html
        -- https://taplo.tamasfe.dev/configuration/formatter-options.html
        append_args = function(_self, _ctx)
          if
            helpers.find_file_upward({
              '.taplo.toml',
              'taplo.toml',
            })
          then
            return {}
          end
          return {
            'fmt',
            '--option',
            'indent_string=  ',
            '--option',
            'indent_tables=true',
            '--option',
            'indent_entries=true',
            '$FILENAME',
          }
        end,
      },
    },
  })

  -- keymaps
  local function format()
    local formatted =
      conform.format({ lsp_fallback = true, async = false, timeout_ms = 2000 })
    if not formatted then
      vim.cmd('normal! mzgg=G`z')
    end
  end
  helpers.keymap_set_multi({
    { 'nv', '==', format, { desc = 'Format file' } },
    { 'nC', '<BS>ic', 'ConformInfo', { desc = 'Open conform info GUI' } },
  })
end

return {
  'stevearc/conform.nvim',
  lazy = true,
  event = { 'BufReadPre', 'BufNewFile' },
  config = config,
}
