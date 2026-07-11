local h = require('lpke.snippets.ls_helpers')

local s = h.s
local t = h.t
local i = h.i
local rep = h.rep

local static_tailwind_css = {
  { 'flex', 'display: flex;' },
  { 'flex-row', 'flex-direction: row;' },
  { 'flex-col', 'flex-direction: column;' },
  { 'grid', 'display: grid;' },
  { 'hidden', 'display: none;' },
  { 'block', 'display: block;' },
  { 'inline-block', 'display: inline-block;' },
  { 'absolute', 'position: absolute;' },
  { 'relative', 'position: relative;' },
  { 'fixed', 'position: fixed;' },
  { 'sticky', 'position: sticky;' },
  { 'w-full', 'width: 100%;' },
  { 'h-full', 'height: 100%;' },
  { 'rounded', 'border-radius: 0.25rem;' },
  { 'border', 'border: 1px solid currentColor;' },
  { 'justify-start', 'justify-content: flex-start;' },
  { 'justify-center', 'justify-content: center;' },
  { 'justify-end', 'justify-content: flex-end;' },
  { 'justify-between', 'justify-content: space-between;' },
  { 'justify-around', 'justify-content: space-around;' },
  { 'justify-evenly', 'justify-content: space-evenly;' },
  { 'items-start', 'align-items: flex-start;' },
  { 'items-center', 'align-items: center;' },
  { 'items-end', 'align-items: flex-end;' },
  { 'items-baseline', 'align-items: baseline;' },
  { 'items-stretch', 'align-items: stretch;' },
  { 'flex-wrap', 'flex-wrap: wrap;' },
  { 'flex-nowrap', 'flex-wrap: nowrap;' },
  { 'text-left', 'text-align: left;' },
  { 'text-center', 'text-align: center;' },
  { 'text-right', 'text-align: right;' },
  { 'text-justify', 'text-align: justify;' },
  { 'bg-blue', 'background: lightblue;' },
  { 'bg-green', 'background: lightgreen;' },
  { 'bg-red', 'background: lightpink;' },
  { 'bg-gray', 'background: lightgray;' },
  { 'bg-grey', 'background: lightgrey;' },
  { 'shadow-xs', 'box-shadow: 0 2px 4px -1px rgb(0 0 0 / 0.12);' },
  {
    'shadow-sm',
    'box-shadow: 0 3px 5px -1px rgb(0 0 0 / 0.18), 0 1px 3px -1px rgb(0 0 0 / 0.18);',
  },
  {
    'shadow-md',
    'box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.2), 0 2px 4px -2px rgb(0 0 0 / 0.2);',
  },
  {
    'shadow-lg',
    'box-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.22), 0 4px 6px -4px rgb(0 0 0 / 0.22);',
  },
  {
    'shadow-xl',
    'box-shadow: 0 20px 25px -5px rgb(0 0 0 / 0.25), 0 8px 10px -6px rgb(0 0 0 / 0.25);',
  },
}

local spacing_sides = {
  { '', {} },
  { 't', { 'top' } },
  { 'r', { 'right' } },
  { 'b', { 'bottom' } },
  { 'l', { 'left' } },
  { 'x', { 'left', 'right' } },
  { 'y', { 'top', 'bottom' } },
}

local snippets = {}

local function add_snippet(trig, nodes, condition)
  table.insert(
    snippets,
    s({
      trig = trig,
      name = trig .. ' tailwind to CSS',
    }, nodes, { condition = condition })
  )
end

local function add_static_snippet(trig, declaration, condition)
  add_snippet(trig, { t(declaration), i(1) }, condition)
end

local function add_value_snippet(trig, properties)
  local nodes = {}

  for index, property in ipairs(properties) do
    if index == 1 then
      table.insert(nodes, t(property .. ': '))
      table.insert(nodes, i(1))
    else
      table.insert(nodes, t({ '', property .. ': ' }))
      table.insert(nodes, rep(1))
    end

    table.insert(nodes, t(';'))
  end

  table.insert(nodes, i(0))
  add_snippet(trig, nodes)
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

local function spacing_declarations(property, sides, value)
  local declarations = {}

  for _, spacing_property in ipairs(spacing_properties(property, sides)) do
    table.insert(declarations, spacing_property .. ': ' .. value .. ';')
  end

  return declarations
end

local function add_spacing_snippets(prefix, property)
  for _, side_config in ipairs(spacing_sides) do
    local side_key = side_config[1]
    local sides = side_config[2]
    local trig = prefix .. side_key .. '-'

    add_value_snippet(trig, spacing_properties(property, sides))

    for value = 0, 9 do
      add_static_snippet(
        trig .. value,
        spacing_declarations(property, sides, value .. 'rem')
      )
    end
  end
end

for _, snippet in ipairs(static_tailwind_css) do
  add_static_snippet(snippet[1], snippet[2], snippet[3])
end

add_snippet('grid-cols', {
  t('grid-template-columns: repeat('),
  i(1, '1'),
  t(', minmax(0, 1fr));'),
  i(0),
})

for columns = 1, 9 do
  add_static_snippet(
    'grid-cols-' .. columns,
    'grid-template-columns: repeat(' .. columns .. ', minmax(0, 1fr));'
  )
end

add_spacing_snippets('p', 'padding')
add_spacing_snippets('m', 'margin')

return snippets
