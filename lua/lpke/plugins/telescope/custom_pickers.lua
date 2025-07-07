local builtin = require('telescope.builtin')
local helpers = require('lpke.core.helpers')

local E = {}

function E.find_git_files()
  if helpers.cwd_has_git() then
    builtin.git_files()
  else
    builtin.find_files()
  end
end

function E.grep_yanked()
  builtin.grep_string({ search = vim.fn.getreg('"') })
end

function E.grep_custom()
  builtin.grep_string({ search = vim.fn.input('Grep: ') })
end


return E
