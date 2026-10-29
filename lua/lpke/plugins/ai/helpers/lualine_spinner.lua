local M = require('lualine.component'):extend()
local requests = require('lpke.plugins.ai.helpers.request_state')
local symbols =
  { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

function M:init(options)
  M.super.init(self, options)
  self.spinner_index = 1
  requests.subscribe('lualine_spinner', function()
    require('lualine').refresh({ place = { 'statusline' } })
  end)
end

function M:update_status()
  if requests.busy() then
    self.spinner_index = self.spinner_index % #symbols + 1
    return symbols[self.spinner_index]
  end
end

return M
