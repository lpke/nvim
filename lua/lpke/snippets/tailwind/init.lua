local definitions = require('lpke.snippets.tailwind.definitions')
local h = require('lpke.snippets.ls_helpers')

local M = {}

local function camel_case(property)
  return property:gsub('%-([a-z])', string.upper)
end

local function spacing_properties(property, sides)
  if #sides == 0 then
    return { property }
  end

  local properties = {}
  for _, side in ipairs(sides) do
    table.insert(properties, property .. '-' .. side)
  end
  return properties
end

local function add_snippet(snippets, trig, name, nodes)
  table.insert(snippets, h.s({ trig = trig, name = name }, nodes))
end

local function declaration_nodes(properties, value, format)
  local nodes = {}

  for index, property in ipairs(properties) do
    if index > 1 then
      table.insert(nodes, h.t({ format == 'css' and '' or ',', '' }))
    end

    local formatted_property = format == 'css' and property
      or camel_case(property)
    local prefix = formatted_property .. ': ' .. (format == 'css' and '' or "'")
    local suffix = (format == 'css' and ';' or "'")
    table.insert(nodes, h.t(prefix))

    if type(value) == 'table' then
      table.insert(nodes, h.t(value.prefix or ''))
      table.insert(nodes, index == 1 and h.i(1, value.default) or h.rep(1))
      table.insert(nodes, h.t(value.suffix or ''))
    elseif value == nil then
      table.insert(nodes, index == 1 and h.i(1) or h.rep(1))
    else
      table.insert(nodes, h.t(value))
    end

    table.insert(nodes, h.t(suffix))
  end

  table.insert(nodes, type(value) == 'string' and h.i(1) or h.i(0))
  return nodes
end

local function add_declaration(snippets, trig, properties, value, format)
  local suffix = format == 'css-suffixed' and ';' or ''
  local output_format = format == 'object' and 'object' or 'css'
  local label = output_format == 'object' and 'CSS obj' or 'CSS'
  add_snippet(
    snippets,
    trig .. suffix,
    trig .. ' tailwind to ' .. label,
    declaration_nodes(properties, value, output_format)
  )
end

local function build(format)
  local snippets = {}

  for _, definition in ipairs(definitions.static) do
    add_declaration(
      snippets,
      definition[1],
      { definition[2] },
      definition[3],
      format
    )
  end

  add_declaration(
    snippets,
    'grid-cols',
    { 'grid-template-columns' },
    definitions.grid_columns.dynamic_value,
    format
  )
  for columns = definitions.grid_columns.min, definitions.grid_columns.max do
    add_declaration(
      snippets,
      'grid-cols-' .. columns,
      { 'grid-template-columns' },
      'repeat(' .. columns .. ', minmax(0, 1fr))',
      format
    )
  end

  for _, spacing in ipairs(definitions.spacing) do
    for _, side_config in ipairs(definitions.spacing_sides) do
      local trig = spacing.prefix .. side_config[1] .. '-'
      local properties = spacing_properties(spacing.property, side_config[2])
      add_declaration(snippets, trig, properties, nil, format)

      for value = definitions.spacing_values.min, definitions.spacing_values.max do
        add_declaration(
          snippets,
          trig .. value,
          properties,
          value .. definitions.spacing_values.unit,
          format
        )
      end
    end
  end

  return snippets
end

function M.css()
  return build('css')
end

function M.jsx()
  return require('lpke.core.helpers').concat_arrs(
    build('object'),
    build('css-suffixed')
  )
end

return M
