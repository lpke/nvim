local M = {}

function M.setup(languages)
  local treesitter = require('nvim-treesitter')
  treesitter.setup({ install_dir = vim.fn.stdpath('data') .. '/site' })

  local group = vim.api.nvim_create_augroup('LpkeTreesitter', { clear = true })
  local bootstrapped = false

  local function attach(bufnr)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      return
    end
    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    if not lang or not vim.treesitter.get_parser(bufnr, lang) then
      return
    end
    vim.treesitter.start(bufnr, lang)
    if vim.treesitter.query.get(lang, 'indents') then
      vim.bo[bufnr].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end

  local function attach_loaded()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      attach(bufnr)
    end
  end

  local function bootstrap()
    if bootstrapped or vim.fn.executable('tree-sitter') ~= 1 then
      return
    end
    bootstrapped = true
    -- tree-sitter build reads CC, replacing the legacy compilers option.
    vim.env.CC = vim.env.CC or 'clang'
    treesitter.update():await(function(err)
      if not err then
        treesitter.install(languages):await(vim.schedule_wrap(attach_loaded))
      end
    end)
  end

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    callback = function(event)
      attach(event.buf)
      local lang = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
      if
        lang
        and vim.fn.executable('tree-sitter') == 1
        and require('nvim-treesitter.parsers')[lang]
      then
        treesitter.install({ lang }):await(vim.schedule_wrap(function()
          attach(event.buf)
        end))
      end
    end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'MasonToolsUpdateCompleted',
    callback = bootstrap,
  })
  -- Mason adds its bin directory during setup, which may run after this file.
  vim.schedule(function()
    attach_loaded()
    bootstrap()
  end)
end

return M
