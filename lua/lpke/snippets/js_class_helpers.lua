local h = require('lpke.snippets.ls_helpers')
local sn, t, i, fmt = h.sn, h.t, h.i, h.fmt

local M = {}

local unsupported_modifiers = {
  abstract = true,
  accessor = true,
  declare = true,
  override = true,
  private = true,
  protected = true,
  public = true,
  static = true,
}

local function trim(str)
  return (str:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function char_at(str, index)
  return str:sub(index, index)
end

local function prev_non_space(str, index)
  for i = index - 1, 1, -1 do
    local char = char_at(str, i)
    if not char:match('%s') then
      return char, i
    end
  end
  return nil, nil
end

local function next_non_space(str, index)
  for i = index + 1, #str do
    local char = char_at(str, i)
    if not char:match('%s') then
      return char, i
    end
  end
  return nil, nil
end

local function should_open_angle(str, index)
  local prev_char, prev_index = prev_non_space(str, index)
  local next_char = next_non_space(str, index)
  local immediate_prev = prev_index and char_at(str, index - 1) or nil

  if not prev_char or not next_char then
    return false
  end

  if next_char == '=' then
    return false
  end

  if prev_char == ':' or prev_char == '=' or prev_char == '(' then
    return true
  end

  return immediate_prev ~= nil
    and not immediate_prev:match('%s')
    and prev_char:match('[%w_$#>%]%)]') ~= nil
end

local function new_state()
  return {
    angle = 0,
    block_comment = false,
    brace = 0,
    bracket = 0,
    escape = false,
    line_comment = false,
    paren = 0,
    quote = nil,
  }
end

local function is_top_level(state)
  return state.paren == 0
    and state.bracket == 0
    and state.brace == 0
    and state.angle == 0
    and state.quote == nil
    and not state.line_comment
    and not state.block_comment
end

local function update_state(state, str, index)
  local char = char_at(str, index)
  local next_char = char_at(str, index + 1)

  if state.line_comment then
    if char == '\n' then
      state.line_comment = false
    end
    return
  end

  if state.block_comment then
    if char == '*' and next_char == '/' then
      state.block_comment = false
    end
    return
  end

  if state.quote then
    if state.escape then
      state.escape = false
    elseif char == '\\' then
      state.escape = true
    elseif char == state.quote then
      state.quote = nil
    end
    return
  end

  if char == '/' and next_char == '/' then
    state.line_comment = true
  elseif char == '/' and next_char == '*' then
    state.block_comment = true
  elseif char == '"' or char == "'" or char == '`' then
    state.quote = char
  elseif char == '(' then
    state.paren = state.paren + 1
  elseif char == ')' and state.paren > 0 then
    state.paren = state.paren - 1
  elseif char == '[' then
    state.bracket = state.bracket + 1
  elseif char == ']' and state.bracket > 0 then
    state.bracket = state.bracket - 1
  elseif char == '{' then
    state.brace = state.brace + 1
  elseif char == '}' and state.brace > 0 then
    state.brace = state.brace - 1
  elseif char == '<' and should_open_angle(str, index) then
    state.angle = state.angle + 1
  elseif char == '>' and state.angle > 0 then
    state.angle = state.angle - 1
  end
end

local function split_top_level(str, delimiter)
  local parts = {}
  local state = new_state()
  local start = 1

  for index = 1, #str do
    local char = char_at(str, index)

    if char == delimiter and is_top_level(state) then
      table.insert(parts, trim(str:sub(start, index - 1)))
      start = index + 1
    else
      update_state(state, str, index)
    end
  end

  table.insert(parts, trim(str:sub(start)))
  return parts
end

local function find_top_level(str, delimiter)
  local state = new_state()

  for index = 1, #str do
    local char = char_at(str, index)

    if char == delimiter and is_top_level(state) then
      return index
    end

    update_state(state, str, index)
  end

  return nil
end

local function find_default(str)
  local state = new_state()

  for index = 1, #str do
    local char = char_at(str, index)
    local prev_char = char_at(str, index - 1)
    local next_char = char_at(str, index + 1)

    if
      char == '='
      and is_top_level(state)
      and not prev_char:match('[=<>!]')
      and not next_char:match('[=>]')
    then
      return index
    end

    update_state(state, str, index)
  end

  return nil
end

local function parse_head(head, raw)
  local readonly = false
  local names = {}

  for token in head:gmatch('%S+') do
    if token == 'readonly' then
      readonly = true
    elseif unsupported_modifiers[token] then
      -- Accepted in input but intentionally omitted from generated fields.
    else
      table.insert(names, token)
    end
  end

  if #names ~= 1 then
    return nil, ('invalid field head: `%s`'):format(raw)
  end

  local field_name = names[1]
  local param_name = field_name:gsub('^#', '')

  if
    param_name == ''
    or param_name:match('^[$_%a][$_%w]*$') == nil
    or (field_name:sub(1, 1) ~= '#' and field_name ~= param_name)
  then
    return nil, ('invalid field name: `%s`'):format(field_name)
  end

  return {
    field_name = field_name,
    param_name = param_name,
    readonly = readonly,
  }
end

local function parse_field(raw)
  raw = trim(raw)

  if raw == '' then
    return nil, nil
  end

  local default_index = find_default(raw)
  local before_default = raw
  local default = nil

  if default_index then
    before_default = trim(raw:sub(1, default_index - 1))
    default = trim(raw:sub(default_index + 1))

    if default == '' then
      return nil, ('missing default value: `%s`'):format(raw)
    end
  end

  local type_index = find_top_level(before_default, ':')
  local head = before_default
  local type_text = nil

  if type_index then
    head = trim(before_default:sub(1, type_index - 1))
    type_text = trim(before_default:sub(type_index + 1))

    if type_text == '' then
      return nil, ('missing type: `%s`'):format(raw)
    end
  end

  local optional = false
  if head:sub(-1) == '?' then
    optional = true
    head = trim(head:sub(1, -2))
  end

  local field, error = parse_head(head, raw)
  if error then
    return nil, error
  end

  field.optional = optional
  field.default = default
  field.type = type_text

  return field, nil
end

function M.parse_fields(input)
  local fields = {}
  local errors = {}

  for _, raw_field in ipairs(split_top_level(input, ',')) do
    local field, error = parse_field(raw_field)

    if field then
      table.insert(fields, field)
    elseif error then
      table.insert(errors, error)
    end
  end

  return fields, errors
end

local function field_param(field)
  local param = field.param_name

  if field.type then
    param = param
      .. (field.optional and not field.default and '?: ' or ': ')
      .. field.type
  elseif field.optional and not field.default then
    param = param .. '?'
  end

  if field.default then
    param = param .. ' = ' .. field.default
  end

  return param
end

local function field_declaration(field)
  local declaration = (field.readonly and 'readonly ' or '') .. field.field_name

  if field.optional then
    declaration = declaration .. '?'
  end

  if field.type then
    declaration = declaration .. ': ' .. field.type
  end

  return declaration .. ';'
end

local function field_assignment(field)
  return ('this.%s = %s;'):format(field.field_name, field.param_name)
end

local function text_lines(lines, continuation_indent)
  local indented_lines = {}

  for index, line in ipairs(lines) do
    indented_lines[index] = index == 1 and line or continuation_indent .. line
  end

  return t(indented_lines)
end

function M.render(input)
  local fields, errors = M.parse_fields(input)
  local params = {}
  local assignments = {}
  local declarations = {}

  for _, field in ipairs(fields) do
    table.insert(params, field_param(field))
    table.insert(assignments, field_assignment(field))
    table.insert(declarations, field_declaration(field))
  end

  return {
    assignments = assignments,
    declarations = declarations,
    errors = errors,
    params = table.concat(params, ', '),
  }
end

local function prompt_fields(parent)
  return h.selected_text(parent) or vim.fn.input('Constructor fields: ')
end

local function error_snippet(errors)
  vim.notify(table.concat(errors, '\n'), vim.log.levels.ERROR)
  return sn(nil, fmt('/* <> */', { t(table.concat(errors, '; ')) }))
end

local function constructor_snippet(rendered)
  if #rendered.assignments == 0 then
    return sn(
      nil,
      fmt(
        [[
          constructor(<>) {
            <>
          }
        ]],
        { t(rendered.params), i(1) }
      )
    )
  end

  return sn(
    nil,
    fmt(
      [[
        constructor(<>) {
          <>
        }
      ]],
      { t(rendered.params), text_lines(rendered.assignments, '  ') }
    )
  )
end

function M.constructor(_args, parent)
  local rendered = M.render(prompt_fields(parent))

  if #rendered.errors > 0 then
    return error_snippet(rendered.errors)
  end

  return constructor_snippet(rendered)
end

function M.constructor_with_fields(_args, parent)
  local rendered = M.render(prompt_fields(parent))

  if #rendered.errors > 0 then
    return error_snippet(rendered.errors)
  end

  if #rendered.declarations == 0 then
    return constructor_snippet(rendered)
  end

  return sn(
    nil,
    fmt(
      [[
        <>

        constructor(<>) {
          <>
        }
      ]],
      {
        t(rendered.declarations),
        t(rendered.params),
        text_lines(rendered.assignments, '  '),
      }
    )
  )
end

return M
