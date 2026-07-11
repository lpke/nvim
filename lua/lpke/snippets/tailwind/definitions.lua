local M = {}

M.static = {
  { 'flex', 'display', 'flex' },
  { 'flex-row', 'flex-direction', 'row' },
  { 'flex-col', 'flex-direction', 'column' },
  { 'grid', 'display', 'grid' },
  { 'hidden', 'display', 'none' },
  { 'block', 'display', 'block' },
  { 'inline-block', 'display', 'inline-block' },
  { 'absolute', 'position', 'absolute' },
  { 'relative', 'position', 'relative' },
  { 'fixed', 'position', 'fixed' },
  { 'sticky', 'position', 'sticky' },
  { 'w-full', 'width', '100%' },
  { 'h-full', 'height', '100%' },
  { 'rounded', 'border-radius', '0.25rem' },
  { 'border', 'border', '1px solid currentColor' },
  { 'justify-start', 'justify-content', 'flex-start' },
  { 'justify-center', 'justify-content', 'center' },
  { 'justify-end', 'justify-content', 'flex-end' },
  { 'justify-between', 'justify-content', 'space-between' },
  { 'justify-around', 'justify-content', 'space-around' },
  { 'justify-evenly', 'justify-content', 'space-evenly' },
  { 'content-start', 'align-content', 'flex-start' },
  { 'content-center', 'align-content', 'center' },
  { 'content-end', 'align-content', 'flex-end' },
  { 'content-between', 'align-content', 'space-between' },
  { 'content-around', 'align-content', 'space-around' },
  { 'content-evenly', 'align-content', 'space-evenly' },
  { 'items-start', 'align-items', 'flex-start' },
  { 'items-center', 'align-items', 'center' },
  { 'items-end', 'align-items', 'flex-end' },
  { 'items-baseline', 'align-items', 'baseline' },
  { 'items-stretch', 'align-items', 'stretch' },
  { 'flex-wrap', 'flex-wrap', 'wrap' },
  { 'flex-nowrap', 'flex-wrap', 'nowrap' },
  { 'text-left', 'text-align', 'left' },
  { 'text-center', 'text-align', 'center' },
  { 'text-right', 'text-align', 'right' },
  { 'text-justify', 'text-align', 'justify' },
  { 'bg-blue', 'background', 'lightblue' },
  { 'bg-green', 'background', 'lightgreen' },
  { 'bg-red', 'background', 'lightpink' },
  { 'bg-gray', 'background', 'lightgray' },
  { 'bg-grey', 'background', 'lightgrey' },
  { 'shadow-xs', 'box-shadow', '0 2px 4px -1px rgb(0 0 0 / 0.12)' },
  {
    'shadow-sm',
    'box-shadow',
    '0 3px 5px -1px rgb(0 0 0 / 0.18), 0 1px 3px -1px rgb(0 0 0 / 0.18)',
  },
  {
    'shadow-md',
    'box-shadow',
    '0 4px 6px -1px rgb(0 0 0 / 0.2), 0 2px 4px -2px rgb(0 0 0 / 0.2)',
  },
  {
    'shadow-lg',
    'box-shadow',
    '0 10px 15px -3px rgb(0 0 0 / 0.22), 0 4px 6px -4px rgb(0 0 0 / 0.22)',
  },
  {
    'shadow-xl',
    'box-shadow',
    '0 20px 25px -5px rgb(0 0 0 / 0.25), 0 8px 10px -6px rgb(0 0 0 / 0.25)',
  },
}

M.spacing_sides = {
  { '', {} },
  { 't', { 'top' } },
  { 'r', { 'right' } },
  { 'b', { 'bottom' } },
  { 'l', { 'left' } },
  { 'x', { 'left', 'right' } },
  { 'y', { 'top', 'bottom' } },
}

M.spacing = {
  { prefix = 'p', property = 'padding' },
  { prefix = 'm', property = 'margin' },
}

M.grid_columns = { min = 1, max = 9 }
M.grid_columns.dynamic_value = {
  prefix = 'repeat(',
  default = '1',
  suffix = ', minmax(0, 1fr))',
}
M.spacing_values = { min = 0, max = 9, unit = 'rem' }

return M
