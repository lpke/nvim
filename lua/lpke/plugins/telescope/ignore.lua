local M = {}

-- Add/remove defaults here. Keep patterns narrow so real project files do not
-- disappear from Telescope. Names are exact basenames; globs use rg/fd syntax.
M.default_ignored = {
  dir_names = {
    '.git',
    '.hg',
    '.svn',
    'node_modules',
    '.idea',
    '.vscode',
    '.vercel',
    '.next',
    '.nuxt',
    '.svelte-kit',
    'build',
    'dist',
    'target',
    'coverage',
    '.cache',
    '.Trash',
    'Trash',
    '__pycache__',
    '.direnv',
    '.npm',
    '.pnpm-store',
    '.pytest_cache',
    '.mypy_cache',
    '.ruff_cache',
    '.parcel-cache',
    '.turbo',
    '.gradle',
    '.terraform',
    '.tox',
    '.venv',
    'venv',
    '.nyc_output',
  },
  file_names = {
    'pnpm-lock.yaml',
    'yarn.lock',
    'package-lock.json',
    'lazy-lock.json',
    '.DS_Store',
    'Thumbs.db',
    'desktop.ini',
    '.eslintcache',
  },
  file_globs = {
    '*.pyc',
    '*.pyo',
    '*.tsbuildinfo',
  },
  path_globs = {},
}

M.dir_names = M.default_ignored.dir_names
M.file_names = M.default_ignored.file_names
M.file_globs = M.default_ignored.file_globs
M.path_globs = M.default_ignored.path_globs

local function file_glob(pattern)
  if pattern:find('/', 1, true) then
    return pattern
  end

  return '**/' .. pattern
end

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

  for _, pattern in ipairs(M.file_globs) do
    vim.list_extend(args, {
      '--glob',
      '!' .. file_glob(pattern),
    })
  end

  for _, pattern in ipairs(M.path_globs) do
    vim.list_extend(args, {
      '--glob',
      '!' .. pattern,
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

  for _, pattern in ipairs(M.file_globs) do
    vim.list_extend(args, {
      '--exclude',
      pattern,
    })
  end

  for _, pattern in ipairs(M.path_globs) do
    vim.list_extend(args, {
      '--exclude',
      pattern,
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
