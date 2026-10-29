local files = require('codecompanion.utils.files')
local log = require('codecompanion.utils.log')

local M = {}
M.__index = M

function M.new(args)
  return setmetatable({
    Chat = args.Chat,
    config = args.config,
    file = require('codecompanion.interactions.shared.slash_commands.file').new(
      args
    ),
  }, M)
end

function M.enabled(chat)
  return chat.adapter.opts and chat.adapter.opts.vision == true,
    'The image Slash Command is not enabled for this adapter'
end

function M:output(selected)
  local mimetype = selected.mimetype or files.get_mimetype(selected.path)
  if not mimetype or not mimetype:match('^image/') then
    return log:warn('The selected file is not an image')
  end
  return self.file:output(selected)
end

function M:pick_file()
  local opts = self.config.opts
  local dirs = vim.list_extend({ vim.fn.getcwd() }, opts.dirs or {})
  local extensions = opts.filetypes
  local output = function(selected)
    return self:output({ path = selected.path or selected[1] })
  end

  if opts.provider == 'default' then
    local picker = require('codecompanion.providers.slash_commands.default')
      .new({ output = output, title = 'Images' })
      :find_files({ dirs = dirs })
    picker.to_display = vim.tbl_filter(function(item)
      return vim.tbl_contains(
        extensions,
        vim.fn.fnamemodify(item.path, ':e'):lower()
      )
    end, picker.to_display)
    return picker:display()
  end

  local picker =
    require('codecompanion.providers.slash_commands.telescope').new({
      output = output,
      title = 'Images',
    })
  local command = { 'fd', '--type', 'f', '--follow', '--hidden' }
  for _, extension in ipairs(extensions) do
    vim.list_extend(command, { '--extension', extension })
  end
  return picker.provider.find_files({
    find_command = command,
    prompt_title = picker.title,
    attach_mappings = picker:display(),
    search_dirs = dirs,
  })
end

function M:pick_url()
  vim.ui.input({ prompt = 'Enter the URL: ' }, function(url)
    url = vim.trim(url or '')
    if url == '' then
      return
    end
    files.download(url, {
      callback = function(err, file)
        if err then
          return log:error(err)
        end
        self:output({
          path = file.path,
          id = url,
          name = url,
          mimetype = file.mimetype,
        })
      end,
    })
  end)
end

function M:execute()
  vim.ui.select(
    { 'URL', 'File' },
    { prompt = 'Select an image source' },
    function(choice)
      if choice == 'File' then
        self:pick_file()
      elseif choice == 'URL' then
        self:pick_url()
      end
    end
  )
end

return M
