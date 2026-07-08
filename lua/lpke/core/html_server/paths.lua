local M = {}

local RELOAD_EXTENSIONS = {
  avif = true,
  cjs = true,
  css = true,
  gif = true,
  htm = true,
  html = true,
  ico = true,
  jpeg = true,
  jpg = true,
  js = true,
  json = true,
  jsx = true,
  map = true,
  mjs = true,
  png = true,
  svg = true,
  ts = true,
  tsx = true,
  txt = true,
  wasm = true,
  webmanifest = true,
  webp = true,
  woff = true,
  woff2 = true,
  xml = true,
}

function M.normalize(path)
  if not path or path == '' then
    return nil
  end
  path = vim.fn.fnamemodify(path, ':p')
  if vim.fs and vim.fs.normalize then
    path = vim.fs.normalize(path)
  end
  if #path > 1 then
    path = path:gsub('/+$', '')
  end
  return path
end

function M.join(dir, name)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(dir, name)
  end
  return dir:gsub('/+$', '') .. '/' .. name
end

function M.is_html(path)
  return type(path) == 'string' and path:lower():match('%.html?$') ~= nil
end

function M.is_under(path, root)
  if not path or not root then
    return false
  end
  if path == root then
    return true
  end
  if root == '/' then
    return path:sub(1, 1) == '/'
  end
  return path:sub(1, #root + 1) == root .. '/'
end

function M.relative(path, root)
  if path == root then
    return ''
  end
  return path:sub(#root + 2)
end

local function url_encode(value)
  return tostring(value):gsub('[^%w%-%._~]', function(char)
    return string.format('%%%02X', char:byte())
  end)
end

function M.url_encode_path(path)
  local parts = {}
  for part in path:gmatch('[^/]+') do
    table.insert(parts, (url_encode(part)))
  end
  return '/' .. table.concat(parts, '/')
end

function M.root_for(path)
  local git_root = nil
  if type(Lpke_find_git_root) == 'function' then
    git_root = Lpke_find_git_root(path)
  end
  git_root = M.normalize(git_root)
  if git_root and M.is_under(path, git_root) then
    return git_root
  end
  return M.normalize(vim.fn.fnamemodify(path, ':h'))
end

function M.should_reload_on_save(path)
  local ext = path and path:match('%.([^./]+)$')
  return ext and RELOAD_EXTENSIONS[ext:lower()] == true
end

function M.node_script()
  local script = vim.api.nvim_get_runtime_file(
    'lua/lpke/core/html_server/node_server.js',
    false
  )[1]
  if script and script ~= '' then
    return script
  end
  return M.join(
    vim.fn.stdpath('config'),
    'lua/lpke/core/html_server/node_server.js'
  )
end

return M
