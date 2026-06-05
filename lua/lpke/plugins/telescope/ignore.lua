local M = {}

M.dir_names = {
  '.git',
  'node_modules',
  '.idea',
  '.vscode',
  '.vercel',
  '.next',
  'build',
  'dist',
}

M.file_names = {
  'pnpm-lock.yaml',
  'yarn.lock',
  'package-lock.json',
  'lazy-lock.json',
}

local function extend_with_rg_ignore_globs(args)
  for _, name in ipairs(M.dir_names) do
    vim.list_extend(args, {
      '--glob',
      '!**/' .. name .. '/**',
    })
  end

  for _, name in ipairs(M.file_names) do
    vim.list_extend(args, {
      '--glob',
      '!**/' .. name,
    })
  end

  return args
end

local function extend_with_fd_excludes(args)
  for _, name in ipairs(M.dir_names) do
    vim.list_extend(args, {
      '--exclude',
      name,
    })
  end

  for _, name in ipairs(M.file_names) do
    vim.list_extend(args, {
      '--exclude',
      name,
    })
  end

  return args
end

function M.rg_restricted_args()
  return extend_with_rg_ignore_globs({
    '--hidden',
  })
end

function M.rg_unrestricted_args()
  return {
    '--hidden',
    '--no-ignore',
    '--no-ignore-parent',
  }
end

function M.fd_restricted_args()
  return extend_with_fd_excludes({
    '--hidden',
  })
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
