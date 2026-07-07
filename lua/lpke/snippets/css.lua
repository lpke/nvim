local h = require('lpke.snippets.ls_helpers')

local s = h.s
local t = h.t
local i = h.i

local tailwind_css = {
  { 'flex', 'display: flex;' },
  { 'flex-row', 'flex-direction: row;' },
  { 'flex-col', 'flex-direction: column;' },
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
}

local snippets = {}

for _, snippet in ipairs(tailwind_css) do
  local trig = snippet[1]
  local declaration = snippet[2]

  table.insert(
    snippets,
    s({
      trig = trig,
      name = trig .. ' tailwind to CSS',
    }, { t(declaration), i(1) })
  )
end

return snippets
