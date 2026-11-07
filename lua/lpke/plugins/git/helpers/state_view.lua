local M = {}

function M.literal_paths(spec, fallback)
  local paths = spec.paths_b64
      and vim.tbl_map(vim.base64.decode, spec.paths_b64)
    or spec.paths
    or fallback
    or {}
  return vim.tbl_map(function(path)
    return ':(top,literal)' .. (path == '.' and '' or path)
  end, paths)
end

-- Keep repository discovery byte-safe for every startup review kind.
function M.create_adapter(root)
  local utils = require('diffview.utils')
  local GitAdapter = require('diffview.vcs.adapters.git').GitAdapter
  -- This dedicated review process does not track Harpoon offsets. Its BufLeave
  -- persistence cannot JSON-encode repositories whose names contain raw bytes.
  if package.loaded.harpoon then
    require('harpoon').get_global_settings().save_on_change = false
  end
  -- Plugin discovery trims both paths. Use the known repository root and a
  -- byte-safe git-dir lookup so whitespace and invalid UTF-8 remain filenames.
  local get_dir = GitAdapter.get_dir
  GitAdapter.get_dir = function(self, path)
    local result = vim
      .system(
        utils.vec_join(
          { self:bin() },
          self:args(),
          { 'rev-parse', '--absolute-git-dir' }
        ),
        { cwd = path }
      )
      :wait()
    return result.code == 0 and result.stdout:gsub('\n$', '') or nil
  end
  local ok, err, adapter = pcall(GitAdapter.create, root, {}, root)
  GitAdapter.get_dir = get_dir
  if not ok then
    error(err)
  end
  if err then
    error(err)
  end
  return adapter
end

-- Scope overrides to this review. Ordinary DiffviewOpen keeps its file list.
-- configure runs before opening, so callers can specialize this view safely.
function M.open(spec, configure)
  local root = spec.repo_b64 and vim.base64.decode(spec.repo_b64)
    or vim.uv.cwd()
  local adapter = M.create_adapter(root)
  local state_args = {
    staged = { '--cached', '--untracked-files=no' },
    unstaged = { '--untracked-files=no' },
    untracked = { '--untracked-files=all' },
    conflicted = { '--untracked-files=no' },
  }
  local args =
    vim.list_extend(vim.deepcopy(spec.args or {}), state_args[spec.state] or {})
  local argo = require('diffview.arg_parser').parse(args)
  local options = adapter:diffview_options(argo)
  if not options then
    return
  end
  local view = require('diffview.scene.views.diff.diff_view').DiffView({
    adapter = adapter,
    path_args = {},
    left = options.left,
    right = options.right,
    options = options.options,
  })
  if not view:is_valid() then
    return
  end
  require('diffview.lib').add_view(view)

  M.configure(view, spec)
  if configure then
    configure(view)
  end
  view:open()
  return view
end

-- Reuse the literal Git records and buffer handling in history/stash views.
function M.configure(view, spec)
  local async = require('diffview.async')
  local FileEntry = require('diffview.scene.file_entry').FileEntry
  local RevType = require('diffview.vcs.rev').RevType
  local utils = require('diffview.utils')
  local adapter = view.adapter
  local argo = require('diffview.arg_parser').parse(spec.args or {})
  local patches = {}
  if view.update_files then
    local update_files = view.update_files
    view.update_files = function(self, callback)
      -- Diffview shares a trailing debounce across all diff views. A hidden
      -- startup tab must not replace the active tab's pending refresh; the
      -- plugin checks focus only after that shared timer has already fired.
      if not self:is_cur_tabpage() then
        if callback then
          callback({ 'The update was cancelled.' })
        end
        return
      end
      return update_files(self, callback)
    end
  end
  local function exact_local_buffers(entry)
    for _, file in ipairs(entry.layout:files()) do
      if file.rev.type == RevType.LOCAL then
        local stat = vim.uv.fs_lstat(file.absolute_path)
        if stat and stat.type == 'link' then
          file.binary = false
          file._lpke_state_contents = function()
            return vim.split(
              vim.uv.fs_readlink(file.absolute_path) or '',
              '\n',
              { plain = true }
            )
          end
        end
        -- The plugin uses :edit and fnameescape, which cannot represent a
        -- newline filename as one Ex command. Buffer APIs preserve the path.
        file._create_local_buffer = function(self)
          local target = vim.uv.fs_readlink(self.absolute_path)
          if target then
            -- Git stores a symlink's target text, while :edit follows it.
            local name = 'diffview://'
              .. adapter.ctx.dir
              .. '/[local-symlink]/'
              .. self.path
            self.bufnr = utils.find_named_buffer(name)
              or vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_name(self.bufnr, name)
            vim.bo[self.bufnr].modifiable = true
            vim.api.nvim_buf_set_lines(
              self.bufnr,
              0,
              -1,
              false,
              vim.split(target, '\n', { plain = true })
            )
            vim.bo[self.bufnr].modifiable = false
            self:post_buf_created()
            return
          end
          self.bufnr = vim.fn.bufadd(self.absolute_path)
          vim.fn.bufload(self.bufnr)
          vim.bo[self.bufnr].buflisted = true
          vim.bo[self.bufnr].bufhidden = 'hide'
          self:post_buf_created()
        end
      end
    end
    return entry
  end
  view.path_args = M.literal_paths(spec, argo.post_args)
  adapter.ctx.path_args = view.path_args
  view.panel.path_args = view.path_args

  -- Escape display text without changing the paths used by Git or file buffers.
  local render = view.panel.render
  view.panel.render = function(self, ...)
    local Component = require('diffview.renderer').RenderComponent
    local add_text = Component.add_text
    local add_line = Component.add_line
    Component.add_text = function(component, text, hl)
      if text == 'Changes ' and spec.state == 'stash' then
        text = 'Saved tracked + untracked '
      elseif text == 'Staged changes ' and spec.state == 'stash' then
        text = 'Saved staged '
      elseif text == 'Changes ' and spec.state == 'staged' then
        text, hl = 'Staged ', 'DiffviewFilePanelStagedTitle'
      elseif text == 'Changes ' and spec.state == 'untracked' then
        text = 'Untracked '
      end
      return add_text(component, text:gsub('\n', '\\n'), hl)
    end
    Component.add_line = function(component, text, hl)
      return add_line(component, text and text:gsub('\n', '\\n'), hl)
    end
    local ok, err = pcall(render, self, ...)
    Component.add_text = add_text
    Component.add_line = add_line
    if not ok then
      error(err)
    end
  end

  local run = async.wrap(function(self, args, callback)
    vim.system(
      utils.vec_join({ self:bin() }, self:args(), args),
      { cwd = self.ctx.toplevel },
      vim.schedule_wrap(function(result)
        callback(result)
      end)
    )
  end)

  adapter.tracked_files = async.wrap(
    function(self, left, right, args, kind, opt, callback)
      -- Index -> local normally also asks for HEAD -> index files. Suppress that
      -- second collection before it can enter the panel or its navigation list.
      if
        spec.state == 'untracked'
        or (
          spec.state
          and spec.state ~= 'staged'
          and spec.state ~= 'stash'
          and kind == 'staged'
        )
      then
        callback(nil, {}, {})
        return
      end
      -- Stock Diffview splits tracked paths on tabs/newlines and suppresses
      -- submodules. NUL records preserve filenames and expose every requested file.
      local result = async.await(
        run(
          self,
          utils.vec_join(
            { 'diff', '--name-status', '-z', '--ignore-submodules=none' },
            args
          )
        )
      )
      if result.code ~= 0 then
        callback({ result.stderr }, nil)
        return
      end
      local records = vim.split(result.stdout, '\0', { plain = true })
      local changes, conflicts = {}, {}
      local i = 1
      while i < #records do
        local status = records[i]:sub(1, 1)
        local path, oldpath = records[i + 1], nil
        i = i + 2
        if status == 'R' or status == 'C' then
          oldpath, path = path, records[i]
          i = i + 1
        end
        changes[#changes + 1] =
          { path = path, oldpath = oldpath, status = status }
        if status == 'U' then
          conflicts[path] = true
        end
      end
      local stats = async.await(
        run(
          self,
          utils.vec_join(
            { 'diff', '--numstat', '-z', '--ignore-submodules=none' },
            args
          )
        )
      )
      if stats.code ~= 0 then
        callback({ stats.stderr }, nil)
        return
      end
      local numbers = vim.split(stats.stdout, '\0', { plain = true })
      local by_path = {}
      i = 1
      while i < #numbers do
        local additions, deletions, path =
          numbers[i]:match('^([^\t]+)\t([^\t]+)\t(.*)$')
        i = i + 1
        if path == '' then
          path, i = numbers[i + 1], i + 2
        end
        if path and tonumber(additions) and tonumber(deletions) then
          by_path[path] =
            { additions = tonumber(additions), deletions = tonumber(deletions) }
        end
      end
      local raw = async.await(
        run(
          self,
          utils.vec_join(
            { 'diff', '--raw', '-z', '--ignore-submodules=none' },
            args
          )
        )
      )
      if raw.code ~= 0 then
        callback({ raw.stderr }, nil)
        return
      end
      local raw_records = vim.split(raw.stdout, '\0', { plain = true })
      local submodules, symlinks = {}, {}
      i = 1
      while i < #raw_records do
        local oldmode, newmode, status =
          raw_records[i]:match('^:(%d+) (%d+) %S+ %S+ (%a)')
        local path = raw_records[i + 1]
        i = i + 2
        if status == 'R' or status == 'C' then
          path, i = raw_records[i], i + 1
        end
        if oldmode == '160000' or newmode == '160000' then
          submodules[path] = true
        end
        symlinks[path] = { oldmode == '120000', newmode == '120000' }
      end
      local files, merge_files = {}, {}
      for _, change in ipairs(changes) do
        if spec.state == 'conflicted' or (not spec.state and kind == 'working' and change.status == 'U') then
          if change.status == 'U' then
            merge_files[#merge_files + 1] =
              exact_local_buffers(FileEntry.with_layout(opt.merge_layout, {
                adapter = self,
                path = change.path,
                status = 'U',
                kind = 'conflicting',
                revs = {
                  a = self.Rev(RevType.STAGE, 2),
                  b = self.Rev(RevType.LOCAL),
                  c = self.Rev(RevType.STAGE, 3),
                  d = self.Rev(RevType.STAGE, 1),
                },
              }))
          end
        elseif not conflicts[change.path] then
          local entry_opt = {
            adapter = self,
            path = change.path,
            oldpath = change.oldpath,
            status = change.status,
            stats = by_path[change.path],
            kind = kind,
            revs = { a = left, b = right },
          }
          if submodules[change.path] then
            local patch = async.await(
              run(
                self,
                utils.vec_join(
                  {
                    'diff',
                    '--submodule=diff',
                    '--no-color',
                    '--no-ext-diff',
                    '--ignore-submodules=none',
                  },
                  self:rev_to_args(left, right),
                  { '--', ':(top,literal)' .. change.path }
                )
              )
            )
            if patch.code ~= 0 then
              callback({ patch.stderr }, nil)
              return
            end
            local lines =
              vim.split(patch.stdout:gsub('\n$', ''), '\n', { plain = true })
            local patch_key = right:object_name()
              .. ':'
              .. kind
              .. ':'
              .. change.path
            patches[patch_key] = lines
            entry_opt.revs = {
              a = self.Rev(RevType.CUSTOM),
              b = right.type == RevType.COMMIT and right
                or self.Rev(RevType.CUSTOM),
            }
            entry_opt.nulled = false
            entry_opt.get_data = function()
              return patches[patch_key]
            end
          end
          local entry = FileEntry.with_layout(opt.default_layout, entry_opt)
          local link_modes = symlinks[change.path] or {}
          if link_modes[1] then
            entry.layout.a.file.binary = false
          end
          if link_modes[2] then
            entry.layout.b.file.binary = false
            entry.layout.b.file._lpke_state_contents = entry_opt.get_data
          end
          if submodules[change.path] then
            entry.layout.a.file.nulled = true
            entry.layout.b.file.binary = false
            entry.layout.b.file.winbar = ' SUBMODULE PATCH - '
              .. change.path:gsub('\n', '\\n')
          end
          files[#files + 1] = exact_local_buffers(entry)
        end
      end
      callback(nil, files, merge_files)
    end
  )

  if not spec.state or spec.state == 'untracked' then
    adapter.untracked_files = async.wrap(
      function(self, left, right, opt, callback)
        -- Diffview's built-in listing is line-delimited and ignores path_args.
        -- Ask Git for NUL-delimited literal paths so brackets, wildcards, tabs
        -- and newlines remain exact filenames, including after a refresh.
        local args = utils.vec_join(
          { self:bin() },
          self:args(),
          { 'ls-files', '--others', '--exclude-standard', '-z', '--' },
          view.path_args
        )
        vim.system(
          args,
          { cwd = self.ctx.toplevel },
          vim.schedule_wrap(function(result)
            if result.code ~= 0 then
              callback({ result.stderr }, nil)
              return
            end
            local files = {}
            for path in result.stdout:gmatch('([^%z]+)%z') do
              files[#files + 1] =
                exact_local_buffers(FileEntry.with_layout(opt.default_layout, {
                  adapter = self,
                  path = path,
                  status = '?',
                  kind = 'working',
                  revs = { a = left, b = right },
                }))
            end
            callback(nil, files)
          end)
        )
      end
    )
  end

  -- Diffview retains entries with unchanged paths during refresh. Keep the
  -- scratch representations current even when their original File survives.
  view.emitter:on('files_updated', function()
    for _, entry in view.files:iter() do
      for _, file in ipairs(entry.layout:files()) do
        if
          file._lpke_state_contents
          and file.bufnr
          and vim.api.nvim_buf_is_loaded(file.bufnr)
        then
          local modifiable = vim.bo[file.bufnr].modifiable
          vim.bo[file.bufnr].modifiable = true
          vim.api.nvim_buf_set_lines(
            file.bufnr,
            0,
            -1,
            false,
            file._lpke_state_contents()
          )
          vim.bo[file.bufnr].modifiable = modifiable
          vim.bo[file.bufnr].modified = false
        end
      end
    end
  end)
end

return M
