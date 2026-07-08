local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local conf = require('telescope.config').values
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local previewers = require('telescope.previewers')
local snippet_types = require('luasnip.util.types')

local ft_aliases = {
  javascript = 'js',
  javascriptreact = 'jsx',
  typescript = 'ts',
  typescriptreact = 'tsx',
}

local ft_order = {
  all = 1,
  lua = 2,
  html = 3,
  css = 4,
  js = 5,
  jsx = 6,
  ts = 7,
  tsx = 8,
  vue = 9,
}

local function display_ft(filetype)
  return ft_aliases[filetype] or filetype
end

local function normalize_ft(filetype)
  return display_ft(filetype:lower())
end

local function sort_filetypes(filetypes)
  table.sort(filetypes, function(a, b)
    local a_order = ft_order[a] or 1000
    local b_order = ft_order[b] or 1000

    if a_order == b_order then
      return a < b
    end
    return a_order < b_order
  end)
end

local function parse_prompt(prompt)
  prompt = prompt or ''

  local pieces = vim.split(prompt, '  ', {
    plain = true,
    trimempty = false,
  })

  local parsed = {
    search = pieces[1] or '',
    filetypes = {},
  }

  for index = 2, #pieces do
    for filetype in pieces[index]:gmatch('%S+') do
      parsed.filetypes[normalize_ft(filetype)] = true
    end
  end

  return parsed
end

local function has_filetype_filters(filetypes)
  return next(filetypes) ~= nil
end

local function matches_filetype_filters(item, filetype_filters)
  if not has_filetype_filters(filetype_filters) then
    return true
  end

  for _, filetype in ipairs(item.filetypes) do
    local normalized = normalize_ft(filetype)
    if normalized == 'all' or filetype_filters[normalized] then
      return true
    end
  end

  return false
end

local function lines_from(value, fallback)
  if type(value) == 'table' then
    return vim.deepcopy(value)
  end
  if type(value) == 'string' then
    return vim.split(value, '\n', { plain = true })
  end
  return { fallback or '' }
end

local function is_empty_text(text)
  return #text == 0 or (#text == 1 and text[1] == '')
end

local function append_text(lines, text)
  if #lines == 0 then
    table.insert(lines, '')
  end

  for index, chunk in ipairs(text) do
    if index == 1 then
      lines[#lines] = lines[#lines] .. chunk
    else
      table.insert(lines, chunk)
    end
  end
end

local function append_placeholder(lines, node, fallback)
  append_text(lines, { '$' .. tostring(node.pos or fallback) })
end

local render_nodes

local function render_node(lines, node)
  if node.type == snippet_types.textNode then
    append_text(lines, node.static_text or { '' })
  elseif
    node.type == snippet_types.insertNode
    or node.type == snippet_types.exitNode
  then
    local static_text = node.static_text or { '' }
    if not is_empty_text(static_text) then
      append_text(lines, static_text)
    end
    append_placeholder(lines, node, 0)
  elseif
    node.type == snippet_types.snippetNode
    or node.type == snippet_types.snippet
  then
    render_nodes(lines, node.nodes or {})
  elseif node.type == snippet_types.choiceNode then
    local choice = node.choices and node.choices[1]
    if choice then
      render_node(lines, choice)
    else
      append_placeholder(lines, node, 'choice')
    end
  else
    append_placeholder(lines, node, snippet_types.names[node.type] or 'node')
  end
end

render_nodes = function(lines, nodes)
  for _, node in ipairs(nodes) do
    render_node(lines, node)
  end
end

local function expansion_for(snippet)
  local lines = { '' }
  render_nodes(lines, snippet.nodes or {})
  return lines
end

local function snippet_label(trigger, name)
  name = name or trigger

  if name:sub(1, #trigger) == trigger then
    local stripped = vim.trim(name:sub(#trigger + 1))
    if stripped ~= '' then
      return stripped
    end
  end

  return name
end

local function item_title(item)
  return ('%s (%s)'):format(item.trigger, item.label)
end

local function make_display(item)
  return ('%s  %s'):format(item_title(item), table.concat(item.filetypes, ' '))
end

local function make_group_key(item)
  return table.concat({
    item.type,
    item.trigger,
    item.name,
    table.concat(item.description, '\n'),
    table.concat(item.expansion, '\n'),
    tostring(item.wordTrig),
    tostring(item.regTrig),
  }, '\31')
end

local function add_snippet(groups, filetype, kind, snippet)
  if snippet.invalidated or snippet.hidden then
    return
  end

  local trigger = snippet.trigger or snippet.trig
  if not trigger or trigger == '' then
    return
  end

  local name = snippet.name or trigger
  local item = {
    trigger = trigger,
    name = name,
    label = snippet_label(trigger, name),
    type = kind,
    wordTrig = snippet.wordTrig and true or false,
    regTrig = snippet.regTrig and true or false,
    description = lines_from(snippet.description or snippet.dscr, trigger),
    expansion = expansion_for(snippet),
    filetype_set = {},
  }

  local key = make_group_key(item)
  local group = groups[key]
  if not group then
    groups[key] = item
    group = item
  end

  group.filetype_set[display_ft(filetype)] = true
end

local function collect_kind(groups, luasnip, luasnip_type, kind)
  local by_filetype = luasnip.get_snippets(nil, { type = luasnip_type })
  for filetype, snippets in pairs(by_filetype) do
    for _, snippet in ipairs(snippets) do
      add_snippet(groups, filetype, kind, snippet)
    end
  end
end

local function finalize_item(item)
  local filetypes = {}
  for filetype, _ in pairs(item.filetype_set) do
    table.insert(filetypes, filetype)
  end

  sort_filetypes(filetypes)
  item.filetype_set = nil
  item.filetypes = filetypes
  item.title = item_title(item)
  item.display = make_display(item)
  item.ordinal = table.concat({
    item.display,
    item.name,
    table.concat(item.description, '\n'),
    table.concat(item.expansion, '\n'),
  }, ' ')
end

local function collect_snippets()
  local luasnip = require('luasnip')
  local groups = {}

  collect_kind(groups, luasnip, 'snippets', 'snippet')
  collect_kind(groups, luasnip, 'autosnippets', 'autosnippet')

  local items = vim.tbl_values(groups)
  for _, item in ipairs(items) do
    finalize_item(item)
  end

  table.sort(items, function(a, b)
    local a_ft = a.filetypes[1] or ''
    local b_ft = b.filetypes[1] or ''
    local a_order = ft_order[a_ft] or 1000
    local b_order = ft_order[b_ft] or 1000

    if a_order ~= b_order then
      return a_order < b_order
    end
    if a_ft ~= b_ft then
      return a_ft < b_ft
    end
    if a.trigger ~= b.trigger then
      return a.trigger < b.trigger
    end
    return a.name < b.name
  end)

  return items
end

local function filtered_snippets(items, parsed_prompt)
  return vim.tbl_filter(function(item)
    return matches_filetype_filters(item, parsed_prompt.filetypes)
  end, items)
end

local function preview_lines(item)
  local fence_filetype = item.filetypes[1] or ''
  local lines = {
    item.title,
    '',
    'trigger: ' .. item.trigger,
    'type: ' .. item.type,
    'filetypes: ' .. table.concat(item.filetypes, ', '),
    'word trigger: ' .. tostring(item.wordTrig),
    'regex trigger: ' .. tostring(item.regTrig),
    '',
    'description:',
  }

  vim.list_extend(lines, item.description)
  vim.list_extend(lines, {
    '',
    'expands to:',
    '```' .. fence_filetype,
  })
  vim.list_extend(lines, item.expansion)
  table.insert(lines, '```')

  return lines
end

local function open_snippets_dir()
  local snippets_dir =
    vim.fs.joinpath(vim.fn.stdpath('config'), 'lua', 'lpke', 'snippets')
  vim.cmd('tab Oil ' .. vim.fn.fnameescape(snippets_dir))
end

local function setup_preview_buffer(bufnr)
  if vim.b[bufnr].lpke_snippet_preview_initialized then
    return
  end

  vim.bo[bufnr].filetype = 'markdown'
  vim.b[bufnr].lpke_snippet_preview_initialized = true
end

local function snippets(opts)
  opts = opts or {}
  local all_items = collect_snippets()
  local parsed_prompt = parse_prompt(opts.default_text or '')
  local original_on_input_filter_cb = opts.on_input_filter_cb

  opts.on_input_filter_cb = function(prompt)
    parsed_prompt = parse_prompt(prompt)
    local result = original_on_input_filter_cb
        and original_on_input_filter_cb(parsed_prompt.search)
      or {}

    result.prompt = result.prompt or parsed_prompt.search
    return result
  end

  pickers
    .new(opts, {
      prompt_title = 'LuaSnip Snippets',
      initial_mode = opts.initial_mode or 'insert',
      finder = finders.new_dynamic({
        fn = function()
          return filtered_snippets(all_items, parsed_prompt)
        end,
        entry_maker = function(item)
          return {
            value = item,
            display = item.display,
            ordinal = item.ordinal,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = 'Snippet',
        define_preview = function(self, entry)
          setup_preview_buffer(self.state.bufnr)
          vim.api.nvim_buf_set_lines(
            self.state.bufnr,
            0,
            -1,
            false,
            preview_lines(entry.value)
          )
        end,
      }),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            open_snippets_dir()
          end
        end)
        return true
      end,
    })
    :find()
end

return snippets
