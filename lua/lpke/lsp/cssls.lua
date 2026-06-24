local function root_markers_with_field(root_files, new_names, field, fname)
  local path = vim.fn.fnamemodify(fname, ':h')
  local found =
    vim.fs.find(new_names, { path = path, upward = true, type = 'file' })

  for _, file_path in ipairs(found or {}) do
    local file = io.open(file_path, 'r')
    if file then
      for line in file:lines() do
        if line:find(field) then
          root_files[#root_files + 1] = vim.fs.basename(file_path)
          break
        end
      end
      file:close()
    end
  end

  return root_files
end

local function insert_package_json(root_files, field, fname)
  return root_markers_with_field(
    root_files,
    { 'package.json', 'package.json5' },
    field,
    fname
  )
end

local function has_tailwind(root_dir)
  if not root_dir then
    return false
  end

  local fname = vim.api.nvim_buf_get_name(0)
  if fname == '' then
    fname = vim.fs.joinpath(root_dir, '.tailwind-root-probe')
  end

  local root_files = {
    -- Generic
    'tailwind.config.js',
    'tailwind.config.cjs',
    'tailwind.config.mjs',
    'tailwind.config.ts',
    'postcss.config.js',
    'postcss.config.cjs',
    'postcss.config.mjs',
    'postcss.config.ts',
    -- Django
    'theme/static_src/tailwind.config.js',
    'theme/static_src/tailwind.config.cjs',
    'theme/static_src/tailwind.config.mjs',
    'theme/static_src/tailwind.config.ts',
    'theme/static_src/postcss.config.js',
  }

  root_files = insert_package_json(root_files, 'tailwindcss', fname)
  root_files = root_markers_with_field(
    root_files,
    { 'mix.lock', 'Gemfile.lock' },
    'tailwind',
    fname
  )

  return vim.fs.find(root_files, { path = fname, upward = true })[1] ~= nil
end

local function apply_tailwind_css_settings(config, root_dir)
  if not has_tailwind(root_dir) then
    return
  end

  config.settings = vim.tbl_deep_extend('force', config.settings or {}, {
    css = {
      lint = {
        unknownAtRules = 'ignore',
      },
    },
    scss = {
      lint = {
        unknownAtRules = 'ignore',
      },
    },
    less = {
      lint = {
        unknownAtRules = 'ignore',
      },
    },
  })
  config._lpke_tailwind_css_settings = true
end

local function get_setting_section(settings, section)
  if type(section) ~= 'string' or section == '' then
    return settings
  end

  local keys = vim.split(section, '.', { plain = true })
  local value = vim.tbl_get(settings, table.unpack(keys))
  if value == nil then
    return vim.empty_dict()
  end

  return value
end

return {
  handlers = {
    ['workspace/configuration'] = function(_, params, ctx)
      local client = vim.lsp.get_client_by_id(ctx.client_id)
      local settings = client and client.config.settings or {}

      return vim.tbl_map(function(item)
        return get_setting_section(settings, item.section)
      end, params.items or {})
    end,
  },
  before_init = function(_, config)
    apply_tailwind_css_settings(config, config.root_dir)
  end,
  on_init = function(client)
    if client.config._lpke_tailwind_css_settings then
      client.notify('workspace/didChangeConfiguration', {
        settings = client.config.settings,
      })
    end
  end,
  on_new_config = function(config, root_dir)
    apply_tailwind_css_settings(config, root_dir)
  end,
}
