local M = { checks = 0, notices = {} }
table.unpack = table.unpack or unpack
vim.opt.rtp:prepend(vim.fn.getcwd())
for _, name in ipairs({
  'codecompanion.nvim',
  'plenary.nvim',
  'nvim-treesitter',
  'telescope.nvim',
  'nvim-web-devicons',
  'nvim-cmp',
}) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. name)
end
vim.opt.rtp:prepend(vim.fn.stdpath('data') .. '/site')
require('lpke.core.globals')
vim.notify = function(message)
  M.notices[#M.notices + 1] = tostring(message)
end
M.slash = require('lpke.plugins.ai.helpers.slash_commands')
require('codecompanion').setup({
  adapters = {
    http = {
      fixture = function()
        return require('codecompanion.adapters').extend('openai_compatible', {
          name = 'fixture',
          formatted_name = 'Fixture',
          schema = { model = { default = 'fixture', choices = { 'fixture' } } },
        })
      end,
    },
  },
  display = {
    chat = {
      start_in_insert_mode = false,
      show_settings = false,
      auto_scroll = false,
    },
  },
  interactions = {
    chat = {
      adapter = 'codex',
      opts = { completion_provider = 'default' },
      slash_commands = M.slash,
    },
    shared = {
      editor_context = {
        buffer = {
          path = 'lpke.plugins.ai.helpers.editor_context.buffer',
          opts = { default_params = 'diff' },
        },
        diagnostics = {
          path = 'lpke.plugins.ai.helpers.editor_context.diagnostics',
        },
      },
    },
  },
  rules = {
    opts = { chat = { enabled = false }, inline = { autoload = false } },
  },
  skills = { opts = { inline = { autoload = false } } },
})
require('codecompanion.interactions.chat.helpers').create_acp_connection = function(
  chat,
  callback
)
  chat.acp_connection = chat.acp_connection
    or {
      session_id = 'fixture-' .. chat.bufnr,
      get_models = function()
        return {}
      end,
      get_config_options = function()
        return {}
      end,
      build_name_map = function()
        return {}
      end,
      disconnect = function() end,
    }
  if callback then
    callback()
  end
end
function M.check(value, message)
  M.checks = M.checks + 1
  assert(value, message)
end
function M.equal(actual, expected, message)
  M.check(
    vim.deep_equal(actual, expected),
    (message or '')
      .. '\nExpected: '
      .. vim.inspect(expected)
      .. '\nActual: '
      .. vim.inspect(actual)
  )
end
function M.chat()
  return require('codecompanion').chat({
    adapter = 'codex',
    hidden = true,
  })
end
function M.wait(predicate, message)
  M.check(vim.wait(3000, predicate, 10), message)
end
function M.write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile(lines, path)
end
function M.run(argv, cwd)
  local result = vim.system(argv, { cwd = cwd, text = true }):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout
end
function M.done(label)
  print(('PASS %s: %d checks'):format(label, M.checks))
  vim.cmd('qa!')
end
return M
