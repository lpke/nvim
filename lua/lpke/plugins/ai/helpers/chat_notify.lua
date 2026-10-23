return function(message, level)
  vim.schedule(function()
    local previous = vim.o.messagesopt
    vim.o.messagesopt = 'wait:0,'
      .. (previous:match('history:%d+') or 'history:500')
    local ok, err = pcall(vim.notify, message, level or vim.log.levels.INFO, {
      title = 'CodeCompanion',
    })
    vim.o.messagesopt = previous
    if not ok then
      error(err)
    end
  end)
end
