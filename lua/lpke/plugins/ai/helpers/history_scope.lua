local M = {}
local path_helpers = require('lpke.core.helpers')

local patched = false

local function trim(str)
  return (str or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function history()
  return require('codecompanion').extensions.history
end

function M.normalize_path(path)
  return path_helpers.normalize_path(path)
end

function M.project_root(path)
  path = M.normalize_path(path or vim.fn.getcwd())
  if not path then
    return nil
  end

  local ok, utils = pcall(require, 'codecompanion._extensions.history.utils')
  if ok and type(utils.find_project_root) == 'function' then
    return M.normalize_path(utils.find_project_root(path))
  end

  local root = vim.fs.root(path, {
    '.git',
    'package.json',
    'Cargo.toml',
    'pyproject.toml',
    'go.mod',
    'pom.xml',
    '.gitignore',
    'README.md',
  })
  return M.normalize_path(root or path)
end

function M.current_project_root()
  return M.project_root(vim.fn.getcwd())
end

function M.chat_project_root(chat)
  if type(chat) ~= 'table' then
    return nil
  end

  return M.normalize_path(chat.project_root) or M.project_root(chat.cwd)
end

function M.in_project(chat, project_root)
  project_root = M.normalize_path(project_root or M.current_project_root())
  return project_root ~= nil and M.chat_project_root(chat) == project_root
end

function M.parse_scope_prompt(prompt)
  prompt = prompt or ''

  if prompt == '@*' then
    return {
      all_chats = true,
      explicit_scope = true,
      raw_prompt = prompt,
      search = '',
    }
  end

  local search = prompt:match('^@%*  (.+)$')
  if search then
    return {
      all_chats = true,
      explicit_scope = true,
      raw_prompt = prompt,
      search = search,
    }
  end

  return {
    all_chats = false,
    explicit_scope = false,
    raw_prompt = prompt,
    search = prompt,
  }
end

function M.parse_chat_search_prompt(prompt)
  return M.parse_scope_prompt(prompt)
end

function M.parse_history_prompt(prompt)
  prompt = prompt or ''

  local all_filter = prompt:match('^@%*%*  (.+)$')
  if all_filter then
    return {
      all_chats = true,
      content_filter = all_filter,
      explicit_scope = true,
      raw_prompt = prompt,
      search = '',
    }
  end

  local parsed = M.parse_scope_prompt(prompt)
  local content_filter = parsed.search:match('^%*  (.+)$')
    or parsed.search:match('^  (.+)$')

  if content_filter then
    parsed.search = ''
    parsed.content_filter = content_filter
    return parsed
  end

  local title_search
  title_search, content_filter = parsed.search:match('^(.-)  (.+)$')

  if content_filter then
    parsed.search = title_search
    parsed.content_filter = content_filter
  end

  return parsed
end

local function smartcase(prompt)
  return prompt:lower() == prompt
end

function M.search_pattern(prompt, ignorecase)
  prompt = trim(prompt)
  if prompt == '' then
    return nil
  end

  if ignorecase == nil then
    ignorecase = smartcase(prompt)
  end

  local ok, regex = pcall(vim.regex, (ignorecase and '\\c' or '\\C') .. prompt)
  if ok then
    return {
      ignorecase = ignorecase,
      query = prompt,
      regex = regex,
    }
  end

  return {
    ignorecase = ignorecase,
    needle = ignorecase and prompt:lower() or prompt,
    query = prompt,
  }
end

function M.match_col(line, pattern, from_col)
  if type(line) ~= 'string' or not pattern then
    return nil
  end

  from_col = math.max(from_col or 0, 0)

  if pattern.regex then
    if from_col > #line then
      return nil
    end

    local ok, start_col, end_col =
      pcall(pattern.regex.match_str, pattern.regex, line:sub(from_col + 1))
    if not ok or not start_col then
      return nil
    end

    start_col = from_col + start_col
    end_col = from_col + end_col
    if end_col <= start_col then
      return nil
    end

    return start_col, end_col
  end

  local haystack = pattern.ignorecase and line:lower() or line
  local start_col, end_col = haystack:find(pattern.needle, from_col + 1, true)
  if not start_col then
    return nil
  end

  return start_col - 1, end_col
end

function M.line_matches(line, pattern)
  return M.match_col(line, pattern) ~= nil
end

function M.message_content(msg)
  local content = msg and msg.content
  if type(content) == 'string' then
    return content
  end

  if type(content) == 'table' and type(content.content) == 'string' then
    return content.content
  end

  return nil
end

function M.searchable_message(msg)
  return msg
    and msg.role ~= 'system'
    and not (msg.opts and msg.opts.visible == false)
    and M.message_content(msg) ~= nil
end

function M.chat_matches_content(chat, query)
  local pattern = M.search_pattern(query)
  if not pattern then
    return true
  end

  for _, value in ipairs({
    chat and chat.title,
    chat and chat.name,
    chat and chat.save_id,
  }) do
    if type(value) == 'string' and M.line_matches(value, pattern) then
      return true
    end
  end

  for _, msg in ipairs((chat and chat.messages) or {}) do
    if M.searchable_message(msg) then
      for _, line in
        ipairs(vim.split(M.message_content(msg), '\n', { plain = true }))
      do
        if M.line_matches(line, pattern) then
          return true
        end
      end
    end
  end

  return false
end

function M.history_item_matches_content(item, query, cache)
  query = trim(query)
  if query == '' then
    return true
  end

  local save_id = item and item.save_id
  local cache_key = save_id and (save_id .. '\0' .. query) or nil
  if cache and cache_key and cache[cache_key] ~= nil then
    return cache[cache_key]
  end

  local chat = save_id and history().load_chat(save_id) or item
  local matches = M.chat_matches_content(chat or item, query)
  if cache and cache_key then
    cache[cache_key] = matches
  end

  return matches
end

function M.filter_history_items(items, parsed, opts)
  opts = opts or {}
  parsed = parsed or M.parse_history_prompt('')

  local project_root = opts.project_root or M.current_project_root()
  local content_cache = opts.content_cache
  local filtered = {}

  for _, item in ipairs(items or {}) do
    if
      (parsed.all_chats or M.in_project(item, project_root))
      and M.history_item_matches_content(
        item,
        parsed.content_filter,
        content_cache
      )
    then
      table.insert(filtered, item)
    end
  end

  return filtered
end

local function history_picker_title(base_title, parsed)
  parsed = parsed or M.parse_history_prompt('')

  local mode = parsed.all_chats and 'all' or 'cwd'
  if parsed.content_filter and parsed.content_filter ~= '' then
    mode = mode .. ', filtered'
  end

  return string.format('%s (%s)', base_title or 'Saved Chats', mode)
end

local function patch_telescope_history_picker()
  local ok, TelescopePicker =
    pcall(require, 'codecompanion._extensions.history.pickers.telescope')
  if not ok or TelescopePicker._lpke_project_scope then
    return
  end
  TelescopePicker._lpke_project_scope = true

  local original_browse = TelescopePicker.browse
  TelescopePicker.browse = function(self, ...)
    if not (self.config and self.config.item_type == 'chat') then
      return original_browse(self, ...)
    end

    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')
    local finders = require('telescope.finders')
    local pickers = require('telescope.pickers')
    local previewers = require('telescope.previewers')
    local sorters = require('telescope.config').values
    local helpers = require('lpke.core.helpers')

    local parsed_prompt = M.parse_history_prompt('')
    local project_root = M.current_project_root()
    local content_cache = {}
    local prompt_bufnr_ref = nil

    local function update_title()
      if not prompt_bufnr_ref then
        return
      end

      vim.schedule(function()
        local ok_picker, picker =
          pcall(action_state.get_current_picker, prompt_bufnr_ref)
        if
          not ok_picker
          or not picker
          or not picker.layout
          or not picker.layout.prompt
          or not picker.layout.prompt.border
        then
          return
        end

        picker.prompt_title =
          history_picker_title(self.config.title, parsed_prompt)
        pcall(
          picker.layout.prompt.border.change_title,
          picker.layout.prompt.border,
          picker.prompt_title
        )
      end)
    end

    pickers
      .new({}, {
        prompt_title = history_picker_title(self.config.title, parsed_prompt),
        on_input_filter_cb = function(prompt)
          parsed_prompt = M.parse_history_prompt(prompt)
          update_title()
          return { prompt = parsed_prompt.search }
        end,
        finder = finders.new_dynamic({
          fn = function()
            return M.filter_history_items(self.config.items, parsed_prompt, {
              content_cache = content_cache,
              project_root = project_root,
            })
          end,
          entry_maker = function(entry)
            local display_title = self:format_entry(entry)

            return vim.tbl_extend('keep', {
              value = entry,
              display = display_title,
              ordinal = self:get_item_title(entry),
              name = self:get_item_title(entry),
              item_id = self:get_item_id(entry),
            }, entry)
          end,
        }),
        sorter = sorters.generic_sorter({}),
        previewer = previewers.new_buffer_previewer({
          title = self:get_item_name_singular():gsub('^%l', string.upper)
            .. ' Preview',
          define_preview = function(preview_state, entry)
            local lines = self.config.handlers.on_preview(entry)
            if not lines then
              return
            end
            vim.bo[preview_state.state.bufnr].filetype = 'markdown'
            vim.api.nvim_buf_set_lines(
              preview_state.state.bufnr,
              0,
              -1,
              false,
              lines
            )
          end,
        }),
        attach_mappings = function(prompt_bufnr)
          prompt_bufnr_ref = prompt_bufnr

          local delete_selections = function()
            local picker = action_state.get_current_picker(prompt_bufnr)
            local selections = picker:get_multi_selection()

            if #selections == 0 then
              local selection = action_state.get_selected_entry()
              if selection then
                selections = { selection }
              end
            end

            actions.close(prompt_bufnr)

            local chats_to_delete = {}
            for _, selection in ipairs(selections) do
              table.insert(chats_to_delete, selection.value)
            end

            self.config.handlers.on_delete(chats_to_delete)
          end

          local rename_selection = function()
            local selection = action_state.get_selected_entry()
            if not selection then
              return
            end
            actions.close(prompt_bufnr)
            self.config.handlers.on_rename(selection.value)
          end

          local duplicate_selection = function()
            local selection = action_state.get_selected_entry()
            if not selection then
              return
            end
            actions.close(prompt_bufnr)
            self.config.handlers.on_duplicate(selection.value)
          end

          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            if not selection then
              return
            end
            actions.close(prompt_bufnr)
            self.config.handlers.on_select(selection.value)
          end)

          helpers.keymap_set_multi({
            {
              'n',
              self.config.keymaps.delete.n,
              delete_selections,
              { buffer = prompt_bufnr, silent = true, nowait = true },
            },
            {
              'i',
              self.config.keymaps.delete.i,
              delete_selections,
              { buffer = prompt_bufnr, silent = true, nowait = true },
            },
            {
              'n',
              self.config.keymaps.rename.n,
              rename_selection,
              { buffer = prompt_bufnr, silent = true, nowait = true },
            },
            {
              'i',
              self.config.keymaps.rename.i,
              rename_selection,
              { buffer = prompt_bufnr, silent = true, nowait = true },
            },
            {
              'n',
              self.config.keymaps.duplicate.n,
              duplicate_selection,
              { buffer = prompt_bufnr, silent = true, nowait = true },
            },
            {
              'i',
              self.config.keymaps.duplicate.i,
              duplicate_selection,
              { buffer = prompt_bufnr, silent = true, nowait = true },
            },
          })

          return true
        end,
      })
      :find()
  end
end

function M.setup()
  if patched then
    return
  end
  patched = true

  patch_telescope_history_picker()
end

return M
