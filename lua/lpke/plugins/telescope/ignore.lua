local M = {}

function M.rg_restricted_args()
  return {
    '--hidden',
  }
end

function M.rg_unrestricted_args()
  return {
    '--hidden',
    '--no-ignore',
    '--no-ignore-parent',
  }
end

function M.fd_restricted_args()
  return {
    '--hidden',
  }
end

function M.fd_unrestricted_args()
  return {
    '--hidden',
    '--no-ignore',
    '--no-ignore-parent',
  }
end

function M.rg_files_command()
  local args = {
    'rg',
    '--files',
  }

  vim.list_extend(args, M.rg_restricted_args())
  return args
end

function M.rg_grep_args(unrestricted)
  local args = unrestricted and M.rg_unrestricted_args()
    or M.rg_restricted_args()

  vim.list_extend(args, {
    '--no-heading',
    '--with-filename',
    '--line-number',
    '--column',
    '--smart-case',
    '--color=never',
  })

  return args
end

function M.vimgrep_arguments()
  local args = {
    'rg',
    '--follow',
  }

  vim.list_extend(args, M.rg_grep_args(false))

  return args
end

return M
