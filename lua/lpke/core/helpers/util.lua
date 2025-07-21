---@class lpke.core.helpers.util
local M = {}

-- calls a function safely (non-breaking if error)
function M.safe_call(func, silent, fallback)
  local ok, result = pcall(func)
  if ok then
    return result
  else
    if not silent then
      vim.notify('safe_call error: ' .. result, vim.log.levels.ERROR)
    end
    return fallback
  end
end

-- concatenates all arrays (itables) provided as args (in order)
function M.concat_arrs(...)
  local result_table = {}
  -- iterate over all provided tables
  for _, tbl in ipairs({ ... }) do
    for _, item in ipairs(tbl) do
      table.insert(result_table, item)
    end
  end
  return result_table
end

-- filter array (ipairs table) non-destructively
function M.arr_filter(arr, func)
  local filtered_arr = {}
  for index, item in ipairs(arr) do
    if func(item, index) then
      table.insert(filtered_arr, item)
    end
  end
  return filtered_arr
end

-- filter array in place (https://stackoverflow.com/questions/49709998/how-to-filter-a-lua-array-inplace)
function M.arr_filter_inplace(arr, func)
  local new_index = 1
  local size_orig = #arr
  for old_index, v in ipairs(arr) do
    if func(v, old_index) then
      arr[new_index] = v
      new_index = new_index + 1
    end
  end
  for i = new_index, size_orig do
    arr[i] = nil
  end
end

-- merges all tables provided as args (later tables take priority)
function M.merge_tables(...)
  local combined_table = {}
  -- iterate over all provided tables
  for _, tbl in ipairs({ ... }) do
    for key, value in pairs(tbl) do
      combined_table[key] = value
    end
  end
  return combined_table
end

-- if `str` matches an item in `mappings`, return second value for it
-- eg: 'hello', {{'hello', 'hi'}, ...} -> 'hi'
function M.map_string(str, mappings, fallback)
  for _, map in ipairs(mappings) do
    if str == map[1] then
      return map[2]
    end
  end
  return fallback or str
end

-- call a function `count` times - for multiple args, use a table
function M.repeat_function(func, args, count)
  if type(args) == 'table' then
    args = function()
      return table.unpack(args)
    end
  end

  for _i = 1, count do
    func(args)
  end
end

return M
