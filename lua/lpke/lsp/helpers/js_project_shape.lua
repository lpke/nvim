local M = {}

local bundler_config_files = {
  'angular.json',
  'astro.config.js',
  'astro.config.mjs',
  'astro.config.ts',
  'esbuild.config.js',
  'esbuild.config.mjs',
  'esbuild.config.ts',
  'next.config.js',
  'next.config.mjs',
  'next.config.ts',
  'nuxt.config.js',
  'nuxt.config.mjs',
  'nuxt.config.ts',
  'parcel.config.js',
  'parcel.config.mjs',
  'parcel.config.ts',
  'rollup.config.js',
  'rollup.config.mjs',
  'rollup.config.ts',
  'rspack.config.js',
  'rspack.config.mjs',
  'rspack.config.ts',
  'svelte.config.js',
  'svelte.config.ts',
  'vite.config.js',
  'vite.config.mjs',
  'vite.config.ts',
  'webpack.config.js',
  'webpack.config.mjs',
  'webpack.config.ts',
}

local bundler_packages = {
  ['@angular/cli'] = true,
  ['@parcel/core'] = true,
  ['@rspack/core'] = true,
  ['@sveltejs/kit'] = true,
  ['astro'] = true,
  ['esbuild'] = true,
  ['next'] = true,
  ['nuxt'] = true,
  ['parcel'] = true,
  ['react-scripts'] = true,
  ['rolldown'] = true,
  ['rollup'] = true,
  ['rspack'] = true,
  ['svelte'] = true,
  ['tsdown'] = true,
  ['tsup'] = true,
  ['unbuild'] = true,
  ['vite'] = true,
  ['webpack'] = true,
}

local function has_root_file(root_dir, names)
  if not root_dir or root_dir == '' then
    return false
  end

  for _, name in ipairs(names) do
    if vim.fn.filereadable(vim.fs.joinpath(root_dir, name)) == 1 then
      return true
    end
  end

  return false
end

local function has_ts_project_config(root_dir)
  return has_root_file(root_dir, { 'tsconfig.json', 'jsconfig.json' })
end

local function read_package_json(root_dir)
  if not root_dir or root_dir == '' then
    return nil
  end

  local package_json_path = vim.fs.joinpath(root_dir, 'package.json')
  if vim.fn.filereadable(package_json_path) == 0 then
    return nil
  end

  local ok_read, lines = pcall(vim.fn.readfile, package_json_path)
  if not ok_read then
    return nil
  end

  local ok_decode, package_json =
    pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok_decode or type(package_json) ~= 'table' then
    return nil
  end

  return package_json
end

local function has_bundler_dependency(package_json)
  if type(package_json) ~= 'table' then
    return false
  end

  for _, section_name in ipairs({
    'dependencies',
    'devDependencies',
    'optionalDependencies',
    'peerDependencies',
  }) do
    local section = package_json[section_name]
    if type(section) == 'table' then
      for package_name, _ in pairs(section) do
        if bundler_packages[package_name] then
          return true
        end
      end
    end
  end

  return false
end

local function has_bundler_signal(root_dir, package_json)
  return has_root_file(root_dir, bundler_config_files)
    or has_bundler_dependency(package_json)
end

local function html_has_module_script(file_path)
  local ok_read, lines = pcall(vim.fn.readfile, file_path)
  if not ok_read then
    return false
  end

  local html = table.concat(lines, '\n')
  return html:find('<script[^>]-type%s*=%s*["\']module["\']') ~= nil
end

local function has_browser_esm_signal(root_dir)
  if not root_dir or root_dir == '' then
    return false
  end

  for _, pattern in ipairs({ '*.html', 'public/*.html', 'src/*.html' }) do
    for _, file_path in ipairs(vim.fn.globpath(root_dir, pattern, false, true)) do
      if html_has_module_script(file_path) then
        return true
      end
    end
  end

  return false
end

local function has_node_esm_signal(package_json)
  return package_json ~= nil and package_json.type == 'module'
end

local function has_native_esm_signal(root_dir, package_json)
  return has_browser_esm_signal(root_dir) or has_node_esm_signal(package_json)
end

function M.uses_bundler_resolution(root_dir)
  local package_json = read_package_json(root_dir)

  if
    has_ts_project_config(root_dir)
    or has_bundler_signal(root_dir, package_json)
  then
    return true
  end

  if has_native_esm_signal(root_dir, package_json) then
    return false
  end

  return true
end

return M
