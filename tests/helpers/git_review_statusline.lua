-- Capture the production formatter without starting unrelated statusline
-- components or loading AI/provider modules in the isolated review harness.
for _, name in ipairs({
  'lualine_spinner',
  'config',
  'acp_session_options',
  'chat_functions',
  'model_swap',
}) do
  package.loaded['lpke.plugins.ai.helpers.' .. name] = {}
end
local lualine = require('lualine')
local setup, captured = lualine.setup
lualine.setup = function(opts)
  captured = opts
end
require('lpke.plugins.lualine').config()
lualine.setup = setup
for _, section in pairs(captured.sections) do
  for _, component in ipairs(section) do
    if type(component) == 'table' and component[1] == 'filename' then
      return assert(component.fmt)
    end
  end
end
error('missing real buffer-name formatter')
