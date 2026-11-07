"""Real-repository regression tests using the shared isolated Neovim harness.

Run: python3 tests/git_review_regressions.py
Only explicitly opted-in temporary repositories permit Git mutations.
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
from helpers.git_review import Harness, Repo, b64, fixture_environment, probe


class GitReviewRegressions(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='review-regressions-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()

    def mutate(self, repo, state, paths, contents, key):
        spec = repo.spec('diff', state=state, paths_b64=[b64(path) for path in paths])
        # Invoke the real configured keymap, including panel cursor inference.
        extra = '''
local view = require('diffview.lib').views[1]
view.panel:focus()
if view.cur_entry then
  view.panel:set_cur_file(view.cur_entry)
  view.panel:highlight_cur_file()
end
local mapping = vim.fn.maparg(''' + json.dumps(key) + ''', 'n', false, true)
assert(type(mapping.callback) == 'function', 'missing mutation keymap')
mapping.callback()
'''
        probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents=contents)],
              extra, mutation_repo=repo.path)

    def test_scoped_staged_U_preserves_unrelated_index_entries_and_empty_scope(self):
        repo = Repo(self.root / 'scoped staged')
        for path in ('selected', 'unrelated'):
            repo.write(path, 'base\n')
        repo.commit()
        for path in ('selected', 'unrelated'):
            repo.write(path, 'index\n')
        repo.git('add', '-A')
        unrelated = repo.git('rev-parse', ':unrelated')
        contents = {'working:selected': dict(a=['base'], b=['index'])}
        self.mutate(repo, 'staged', ['selected'], contents, 'U')
        self.assertEqual(repo.git('diff', '--cached', '--name-only'), 'unrelated')
        self.assertEqual(repo.git('rev-parse', ':unrelated'), unrelated)
        before = repo.snapshot()
        self.mutate(repo, 'staged', ['selected'], {}, 'U')
        self.assertEqual(repo.snapshot(), before, 'empty scoped U changed the repository')

    def test_inherited_stage_unstage_and_intent_keys_keep_literal_paths(self):
        for key in ('s', 'S', 'U', 'I'):
            for name, collision in (('file*', 'file-other'), ('file[ab]', 'filea'),
                                    (':(glob)*', 'unrelated')):
                with self.subTest(key=key, name=name):
                    repo = Repo(self.root / ('literal-' + key + '-' + str(len(list(self.root.iterdir())))))
                    if key != 'I':
                        for path in (name, collision):
                            repo.write(path, 'base\n')
                        repo.commit()
                    else:
                        repo.write('base', 'base\n')
                        repo.commit()
                    for path in (name, collision):
                        repo.write(path, 'worktree\n')
                    if key == 'U':
                        repo.git('add', '-A')
                    state = 'staged' if key == 'U' else 'untracked' if key == 'I' else 'unstaged'
                    a = [''] if key == 'I' else ['base']
                    self.mutate(repo, state, [name], {
                        'working:' + name: dict(a=a, b=['worktree'])}, key)
                    changed = repo.git('diff', '--cached', '--name-only', '-z').rstrip('\0').split('\0')
                    if key == 'U':
                        self.assertEqual(changed, [collision])
                    elif key == 'I':
                        self.assertEqual(repo.git('ls-files', '-z').split('\0')[:-1], sorted(['base', name]))
                        self.assertEqual(repo.git('show', ':' + name), '')
                        self.assertEqual(changed, [''])  # intent, not staged content
                    else:
                        self.assertEqual(changed, [name])
                    for path in (name, collision):
                        self.assertEqual((repo.path / path).read_text(), 'worktree\n')

    def test_inherited_single_entry_unstage_keeps_literal_paths(self):
        # Native toggle requires index -> local, where staged entries are a
        # separate panel section. Exercise that path as well as cached-view U.
        repo = Repo(self.root / 'toggle unstage')
        for path in ('file*', 'file-other'):
            repo.write(path, 'base\n')
        repo.commit()
        for path in ('file*', 'file-other'):
            repo.write(path, 'index\n')
        repo.git('add', '-A')
        spec = repo.spec('diff', paths_b64=[b64('file*')])
        extra = '''
local view = require('diffview.lib').views[1]
view.panel:focus()
view.panel:set_cur_file(view.files.staged[1])
view.panel:highlight_cur_file()
require('diffview.actions').toggle_stage_entry()
'''
        probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
            'staged:file*': dict(a=['base'], b=['index'])})], extra, mutation_repo=repo.path)
        self.assertEqual(repo.git('diff', '--cached', '--name-only'), 'file-other')

    def test_mutation_opt_in_rejects_other_repositories(self):
        intended = Repo(self.root / 'intended')
        sentinel = Repo(self.root / 'sentinel')
        sentinel.write('file', 'untouched\n')
        before = sentinel.snapshot()
        script = self.root / 'denied.lua'
        script.write_text("""
local ok, err = pcall(vim.fn.system, {
  'git', '-C', vim.env.LPKE_TEST_SENTINEL, 'add', '--', 'file',
})
if not ok then
  io.stderr:write(tostring(err) .. '\\n')
  vim.cmd('cquit 1')
else
  print('GIT_REVIEW_PASS')
  vim.cmd('qa!')
end
""")
        with Harness(self.root, script) as harness:
            with self.assertRaisesRegex(AssertionError, 'review harness denied git command add'):
                harness.run(extra_env=dict(LPKE_TEST_SENTINEL=str(sentinel.path)),
                            mutation_repo=intended.path)
        self.assertEqual(sentinel.snapshot(), before)

    def test_copy_detection_reviews_and_unstages_destination_without_source(self):
        repo = Repo(self.root / 'copy detection')
        base = ['line %03d' % i for i in range(100)]
        repo.write('source', '\n'.join(base) + '\n')
        repo.commit()
        repo.git('config', 'status.renames', 'copies')
        repo.git('config', 'diff.renames', 'copies')
        changed = base + ['user edit']
        for path in ('source', 'copy'):
            repo.write(path, '\n'.join(changed) + '\n')
        repo.git('add', '-A')
        self.assertIn('C ', repo.git('status', '--porcelain=v1'))
        source = repo.git('rev-parse', ':source')
        spec = repo.spec('diff', state='staged', exact_paths=True, paths_b64=[b64('source'), b64('copy')])
        extra = '''
local view = require('diffview.lib').views[1]
assert(view.adapter:reset_files({'copy'}))
'''
        probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
            'working:source': dict(a=base, b=changed), 'working:copy': dict(a=[''], b=changed)})],
              extra, mutation_repo=repo.path)
        self.assertEqual(repo.git('rev-parse', ':source'), source)
        self.assertEqual(repo.git('diff', '--cached', '--name-only'), 'source')

    def test_exact_saved_file_reviews_refuse_directory_replacement_on_refresh(self):
        for state in ('staged', 'untracked'):
            with self.subTest(state=state):
                repo = Repo(self.root / ('refresh-' + state))
                repo.write('base', 'base\n')
                if state == 'staged': repo.write('selected', 'base\n')
                repo.commit()
                repo.write('selected', 'shown\n')
                if state == 'staged': repo.git('add', '--', 'selected')
                spec = repo.spec('diff', state=state, exact_paths=True, paths_b64=[b64('selected')])
                extra = '''
local view = require('diffview.lib').views[1]
local root = view.adapter.ctx.toplevel
assert(vim.uv.fs_unlink(root .. '/selected'))
assert(vim.uv.fs_mkdir(root .. '/selected', 448))
local fd = assert(vim.uv.fs_open(root .. '/selected/private', 'w', 384))
assert(vim.uv.fs_write(fd, 'undisplayed private contents\\n', 0))
assert(vim.uv.fs_close(fd))
if ''' + json.dumps(state) + ''' == 'staged' then
  assert(vim.system({'git', '-C', root, 'add', '--', 'selected'}):wait().code == 0)
end
local index = vim.fn.readblob(root .. '/.git/index')
local done, failure = false, nil
view:update_files(function(err) failure, done = err, true end)
assert(vim.wait(5000, function() return done end, 10), 'refresh did not finish')
assert(failure and table.concat(failure, ' '):lower():find('file boundary', 1, true), 'refresh accepted widened scope')
for _, entry in view.files:iter() do assert(entry.path == 'selected', 'private descendant entered review') end
assert(vim.deep_equal(vim.fn.readblob(root .. '/.git/index'), index), 'refusal changed index')
'''
                probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
                    'working:selected': dict(a=['base'] if state == 'staged' else [''], b=['shown'])})],
                      extra, mutation_repo=repo.path)

    def test_root_history_uses_repository_object_format_without_writes(self):
        for object_format in ('sha1', 'sha256'):
            with self.subTest(object_format=object_format):
                repo = Repo(self.root / object_format, object_format=object_format)
                repo.write('file.txt', 'root contents\n')
                root = repo.commit('Root')
                repo.write('file.txt', 'next contents\n')
                tip = repo.commit('Next')
                spec = repo.spec('history', args=['--range=' + tip])
                before = repo.snapshot()
                empty_tree = repo.git('hash-object', '-t', 'tree', '--stdin')
                self.assertFalse((repo.path / '.git/objects' / empty_tree[:2] / empty_tree[2:]).exists())
                probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], commits=[tip, root], versions=[
                    dict(commit=tip, path='file.txt', a=['root contents'], b=['next contents']),
                    dict(commit=root, path='file.txt', a=[''], b=['root contents']),
                ])])
                self.assertEqual(repo.snapshot(), before, 'root history wrote to repository')

    def test_history_and_child_diff_block_restore_and_all_staging_routes(self):
        repo = Repo(self.root / 'immutable history')
        repo.write('file', 'base\n')
        repo.commit()
        repo.write('file', 'committed\n')
        tip = repo.commit()
        repo.write('file', 'user index\n')
        repo.git('add', '--', 'file')
        repo.write('file', 'user worktree\n')
        before = repo.snapshot()
        spec = repo.spec('history', args=['--range=' + tip + '^!'])
        extra = '''
local async = require('diffview.async')
local view = require('diffview.lib').views[1]
local function reject(target)
  target.panel:focus()
  for _, action in ipairs({'restore_entry', 'stage_all', 'unstage_all', 'toggle_stage_entry'}) do
    require('diffview.actions')[action]()
  end
  for _, key in ipairs({'X', 'I', 'S', 'U', 'cc'}) do
    local mapping = vim.fn.maparg(key, 'n', false, true)
    if type(mapping.callback) == 'function' then mapping.callback() end
  end
  assert(target.adapter:add_files({'file'}) == false)
  assert(target.adapter:reset_files({'file'}) == false)
  assert(target.adapter:stage_index_file({}) == false)
  local done, failure = false, nil
  async.void(function()
    local ok, value = async.pawait(target.adapter.file_restore, target.adapter, 'file', 'working')
    if not ok or value ~= false then failure = tostring(value) end
    done = true
  end)()
  assert(vim.wait(5000, function() return done end, 10), 'restore callback hung')
  assert(not failure, failure)
end
reject(view)
require('diffview.actions').open_in_diffview()
assert(vim.wait(5000, function()
  local child = require('diffview.lib').views[2]
  return child and child.initialized and child.cur_entry and child.cur_entry.opened
end, 10), 'child diff failed to load')
local child = require('diffview.lib').views[2]
assert(child._lpke_readonly, 'child lost immutable protection')
reject(child)
for _, file in ipairs(child.cur_entry.layout:files()) do
  assert(not vim.bo[file.bufnr].modifiable and vim.bo[file.bufnr].readonly)
end
'''
        probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], commits=[tip],
              contents={'file': dict(a=['base'], b=['committed'])}, readonly=True)], extra)
        self.assertEqual(repo.snapshot(), before, 'immutable actions changed user state')

    def test_overlapping_history_navigation_serializes_slow_renamed_buffers(self):
        repo = Repo(self.root / 'overlapping history')
        paths = ['first\t*', 'middle\n*', 'last\t*']
        repo.write(paths[0], 'saved contents\n')
        commits = [repo.commit()]
        for old, new in zip(paths, paths[1:]):
            repo.git('mv', '--', old, new)
            commits.append(repo.commit())
        spec = repo.spec('history', paths_b64=[b64(paths[-1])])
        extra = '''
local async = require('diffview.async')
local view = require('diffview.lib').views[1]
assert(vim.wait(5000, function() return view.cur_entry and view.cur_entry.opened end, 10))
view.emitter:on('file_open_post', function(_, entry)
  assert(view.cur_entry == entry, 'completed selection displays a different history entry')
end)
for _, entry in ipairs(view.panel.entries) do
  for _, file_entry in ipairs(entry.files) do
    for _, file in ipairs(file_entry.layout:files()) do
      local produce = file.produce_data
      file.produce_data = async.wrap(function(self, callback)
        vim.defer_fn(function()
          async.void(function()
            local err, lines = async.await(produce(self))
            callback(err, lines)
          end)()
        end, 100)
      end)
    end
  end
end
local done, failure = false, nil
async.void(function()
  local ok, err = pcall(function()
    local tasks = {}
    for index = #view.panel.entries, 1, -1 do
      tasks[#tasks + 1] = view:set_file(view.panel.entries[index].files[1])
    end
    for _, task in ipairs(tasks) do async.await(task) end
    for _, entry in ipairs(view.panel.entries) do
      for _, file in ipairs(entry.files[1].layout:files()) do
        assert(file:is_valid(), 'lost renamed buffer')
        local lines = vim.api.nvim_buf_get_lines(file.bufnr, 0, -1, false)
        assert(vim.deep_equal(lines, {'saved contents'}) or vim.deep_equal(lines, {''}))
      end
    end
  end)
  if not ok then failure = err end
  done = true
end)()
assert(vim.wait(10000, function() return done end, 10), 'navigation hung')
assert(not failure, failure)
'''
        before = repo.snapshot()
        # Metadata-only expectations leave historical buffers unloaded until the
        # deliberately concurrent selections above.
        versions = [dict(commit=oid, path=path) for oid, path in reversed(list(zip(commits, paths)))]
        probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], commits=commits, versions=versions)], extra)
        self.assertEqual(repo.snapshot(), before)

    def test_explicit_commit_diff_is_immutable_too(self):
        repo = Repo(self.root / 'immutable explicit diff')
        repo.write('file', 'base\n')
        base = repo.commit()
        repo.write('file', 'committed\n')
        tip = repo.commit()
        repo.write('file', 'preserve local edits\n')
        before = repo.snapshot()
        spec = repo.spec('diff', args=[base + '..' + tip])
        extra = '''
local view = require('diffview.lib').views[1]
assert(view._lpke_readonly)
view.panel:focus()
require('diffview.actions').restore_entry()
require('diffview.actions').stage_all()
require('diffview.actions').unstage_all()
'''
        probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], readonly=True,
              contents={'working:file': dict(a=['base'], b=['committed'])})], extra)
        self.assertEqual(repo.snapshot(), before)

    def test_restore_key_preserves_literal_hidden_collisions_and_index(self):
        for name, collision in (('file*', 'file-other'), ('file[ab]', 'filea'),
                                (':(glob)*', 'unrelated'), ('line\n*', 'line\nother')):
            with self.subTest(path=name):
                repo = Repo(self.root / ('restore-' + str(len(list(self.root.iterdir())))))
                for path in (name, collision):
                    repo.write(path, 'base\n')
                repo.commit()
                for path in (name, collision):
                    repo.write(path, 'index\n')
                repo.git('add', '-A')
                for path in (name, collision):
                    repo.write(path, 'worktree\n')
                index = {path: repo.git('rev-parse', ':' + path) for path in (name, collision)}
                self.mutate(repo, 'unstaged', [name], {
                    'working:' + name: dict(a=['index'], b=['worktree'])}, 'X')
                self.assertEqual((repo.path / name).read_text(), 'index\n')
                self.assertEqual((repo.path / collision).read_text(), 'worktree\n')
                self.assertEqual({path: repo.git('rev-parse', ':' + path) for path in index}, index)

    def test_tree_directory_actions_expand_only_represented_files(self):
        for staged in (False, True):
            with self.subTest(staged=staged):
                repo = Repo(self.root / ('directory-' + str(staged)))
                paths = ('dir/selected', 'dir/unselected')
                for path in paths:
                    repo.write(path, 'base\n')
                repo.commit()
                for path in paths:
                    repo.write(path, 'changed\n')
                if staged:
                    repo.git('add', '-A')
                spec = repo.spec('diff', paths_b64=[b64(paths[0])])
                prefix = 'staged:' if staged else 'working:'
                extra = '''
local view = require('diffview.lib').views[1]
view.panel.listing_style = 'tree'
view.panel:render()
view.panel:redraw()
view.panel:focus()
local found = false
for row = 1, vim.api.nvim_buf_line_count(view.panel.bufid) do
  vim.api.nvim_win_set_cursor(view.panel.winid, {row, 0})
  local item = view.panel:get_item_at_cursor()
  if item and item.path == 'dir' and type(item.collapsed) == 'boolean' then
    found = true
    break
  end
end
assert(found, 'missing native directory row')
require('diffview.actions').toggle_stage_entry()
'''
                probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
                    prefix + paths[0]: dict(a=['base'], b=['changed'])})], extra, mutation_repo=repo.path)
                self.assertEqual(repo.git('diff', '--cached', '--name-only'), paths[1] if staged else paths[0])
                self.assertEqual([(repo.path / p).read_text() for p in paths], ['changed\n'] * 2)

    def test_individual_rename_unstage_includes_both_endpoints(self):
        for old, new in (('old', 'new'), ('from/old*', 'to/new[ab]'), ('old\nname', 'new\nname')):
            with self.subTest(old=old, new=new):
                repo = Repo(self.root / ('rename-' + str(len(list(self.root.iterdir())))))
                repo.write(old, 'rename contents\n')
                repo.write('unrelated', 'base\n')
                repo.commit()
                (repo.path / new).parent.mkdir(parents=True, exist_ok=True)
                repo.git('mv', '--', old, new)
                repo.write('unrelated', 'keep staged\n')
                repo.git('add', '--', 'unrelated')
                unrelated = repo.git('rev-parse', ':unrelated')
                spec = repo.spec('diff', paths_b64=[b64(old), b64(new)])
                extra = '''
local view = require('diffview.lib').views[1]
view.panel:focus()
view.panel:set_cur_file(view.files.staged[1])
view.panel:highlight_cur_file()
require('diffview.actions').toggle_stage_entry()
'''
                probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
                    'staged:' + new: dict(a=['rename contents'], b=['rename contents'], oldpath=old)})],
                    extra, mutation_repo=repo.path)
                self.assertEqual(repo.git('diff', '--cached', '--name-only'), 'unrelated')
                self.assertEqual(repo.git('rev-parse', ':unrelated'), unrelated)
                self.assertIn(old, repo.git('ls-files', '-z').split('\0'))
                self.assertNotIn(new, repo.git('ls-files', '-z').split('\0'))
                self.assertEqual((repo.path / new).read_text(), 'rename contents\n')

    def test_stale_file_directory_boundaries_refuse_stage_and_unstage(self):
        for action in ('add', 'intent', 'reset', 'index-add', 'index-intent', 'index-reset', 'head-reset', 'index-save'):
            for name in ('selected', 'selected*\n[ab]', 'parent/selected'):
                with self.subTest(action=action, path=name):
                    repo = Repo(self.root / ('stale-' + str(len(list(self.root.iterdir())))))
                    repo.write(name, 'base\n')
                    repo.write('unrelated', 'base\n')
                    original = repo.commit()
                    target = original
                    if action == 'head-reset':
                        (repo.path / name).unlink()
                        repo.write(name + '/hidden', 'hidden target\n')
                        target = repo.commit()
                        repo.git('reset', '--hard', original)
                    repo.write(name, 'changed\n')
                    working_action = action in ('add', 'intent', 'index-add', 'index-intent')
                    if not working_action:
                        repo.git('add', '--', name)
                    spec = repo.spec('diff', state='unstaged' if working_action else 'staged',
                                     paths_b64=[b64(name)])
                    extra = '''
local view = require('diffview.lib').views[1]
local root, path = view.adapter.ctx.toplevel, vim.base64.decode(''' + json.dumps(b64(name)) + ''')
local function git(args, input)
  local result = vim.system(vim.list_extend({'git', '--literal-pathspecs', '-C', root}, args), {stdin=input}):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout
end
local action = ''' + json.dumps(action) + '''
if action:find('index-', 1, true) == 1 then
  local oid = vim.trim(git({'rev-parse', ':' .. path}))
  git({'update-index', '--force-remove', '--', path})
  local changed = path:find('/', 1, true) and path:match('^([^/]+)') or path .. '/hidden'
  git({'update-index', '-z', '--index-info'}, '100644 ' .. oid .. ' 0\t' .. changed .. '\\0')
elseif action == 'head-reset' then
  local fd = assert(vim.uv.fs_open(root .. '/.git/refs/heads/main', 'w', 384))
  assert(vim.uv.fs_write(fd, ''' + json.dumps(target + '\n') + ''', 0))
  assert(vim.uv.fs_close(fd))
else
  assert(vim.uv.fs_unlink(root .. '/' .. path))
  assert(vim.uv.fs_mkdir(root .. '/' .. path, 448))
  local fd = assert(vim.uv.fs_open(root .. '/' .. path .. '/hidden', 'w', 384))
  assert(vim.uv.fs_write(fd, 'hidden contents\\n', 0))
  assert(vim.uv.fs_close(fd))
  if action == 'reset' then git({'add', '--', path}) end
end
local index = vim.fn.readblob(root .. '/.git/index')
local before = git({'ls-files', '--stage', '-z'})
local messages, utils = {}, require('diffview.utils')
local err = utils.err
local notify = vim.notify
utils.err = function(message) messages[#messages + 1] = tostring(message) end
vim.notify = function(message) messages[#messages + 1] = tostring(message) end
local result
if action == 'add' or action == 'index-add' then result = view.adapter:add_files({path})
elseif action == 'intent' or action == 'index-intent' then
  view.panel:focus()
  view.panel:set_cur_file(view.cur_entry)
  view.panel:highlight_cur_file()
  local mapping = vim.fn.maparg('I', 'n', false, true)
  assert(type(mapping.callback) == 'function')
  mapping.callback()
  result = false
elseif action == 'index-save' then result = view.adapter:stage_index_file(view.files.working[1].layout.b.file)
else result = view.adapter:reset_files({path}) end
utils.err = err
vim.notify = notify
assert(result == false, 'stale directory mutation was accepted')
assert(#messages > 0 and messages[1]:lower():find('refresh', 1, true), 'missing refresh explanation')
assert(git({'ls-files', '--stage', '-z'}) == before, 'changed hidden index entries')
assert(vim.deep_equal(vim.fn.readblob(root .. '/.git/index'), index), 'rewrote index on refusal')
'''
                    probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
                        'working:' + name: dict(a=['base'], b=['changed'])})], extra, mutation_repo=repo.path)
                    self.assertEqual((repo.path / 'unrelated').read_text(), 'base\n')

    def test_submodule_staging_and_unstaging_remain_exact_directory_endpoints(self):
        repo = Repo(self.root / 'parent')
        child = Repo(repo.path / 'module')
        child.write('file', 'base\n')
        old = child.commit()
        repo.write('unrelated', 'base\n')
        repo.commit()
        child.write('file', 'changed\n')
        tip = child.commit()
        before = child.snapshot()
        for staged in (False, True):
            spec = repo.spec('diff', state='staged' if staged else 'unstaged', paths_b64=[b64('module')])
            patch = repo.git('diff', *(['--cached'] if staged else []), '--submodule=diff',
                             '--no-ext-diff', '--no-color', '--ignore-submodules=none', '--', 'module').splitlines()
            extra = '''
local view = require('diffview.lib').views[1]
assert(view.adapter:''' + ('reset_files' if staged else 'add_files') + '''({'module'}))
'''
            probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
                'working:module': dict(a=[''], b=patch)})],
                  extra, mutation_repo=repo.path)
            self.assertEqual(repo.git('rev-parse', ':module'), old if staged else tip)
            self.assertEqual(child.snapshot(), before)

    def test_work_role_fallback_matches_chezmoi_prefix_and_explicit_override(self):
        script = self.root / 'work-role.lua'
        script.write_text('''
local ok, err = pcall(function()
local hostname = vim.uv.os_gethostname
local uname = vim.uv.os_uname
local override = vim.env.LPKE_IS_WORK_DEVICE
for _, system in ipairs({'Darwin', 'Linux', 'Windows_NT'}) do
  for _, host in ipairs({'Luke-Perich', 'Luke-Perich-2', 'Luke-Air', 'lpnix', 'luke-perich'}) do
    vim.uv.os_uname = function() return {sysname=system} end
    vim.uv.os_gethostname = function() return host end
    for _, value in ipairs({'unset', '1', '0'}) do
      if value == 'unset' then vim.env.LPKE_IS_WORK_DEVICE = nil
      else vim.env.LPKE_IS_WORK_DEVICE = value end
      dofile(vim.env.XDG_CONFIG_HOME .. '/nvim/lua/lpke/core/globals/globals.lua')
      local expected = host:sub(1, #'Luke-Perich') == 'Luke-Perich'
      if value ~= 'unset' then expected = value == '1' end
      assert(Lpke_is_work_device == expected, system .. '/' .. host .. '/' .. value)
    end
  end
end
vim.uv.os_gethostname, vim.uv.os_uname = hostname, uname
vim.env.LPKE_IS_WORK_DEVICE = override
end)
if not ok then io.stderr:write(tostring(err) .. '\\n'); vim.cmd('cquit 1') end
print('GIT_REVIEW_PASS')
vim.cmd('qa!')
''')
        with Harness(self.root, script) as harness:
            harness.run()

    def test_unborn_scoped_unstage_preserves_unrelated_index_entries(self):
        for object_format in ('sha1', 'sha256'):
            with self.subTest(object_format=object_format):
                repo = Repo(self.root / ('unborn-' + object_format), object_format=object_format)
                for name in ('selected*', 'unrelated'):
                    repo.write(name, 'contents\n')
                repo.git('add', '-A')
                unrelated = repo.git('rev-parse', ':unrelated')
                self.mutate(repo, 'staged', ['selected*'], {
                    'working:selected*': dict(a=[''], b=['contents'])}, 'U')
                self.assertEqual(repo.git('ls-files'), 'unrelated')
                self.assertEqual(repo.git('rev-parse', ':unrelated'), unrelated)

    def test_saving_index_buffer_preserves_literal_bytes_and_unrelated_staging(self):
        for name in ('file*\n[ab]', '-selected'):
            with self.subTest(path=name):
                repo = Repo(self.root / ('index-save-' + str(len(list(self.root.iterdir())))))
                for path in (name, 'file-other'):
                    repo.write(path, 'base\n')
                repo.commit()
                for path in (name, 'file-other'):
                    repo.write(path, 'staged\n')
                repo.git('add', '-A')
                unrelated = repo.git('rev-parse', ':file-other')
                spec = repo.spec('diff', paths_b64=[b64(name)])
                extra = '''
local view = require('diffview.lib').views[1]
local file = view.files.staged[1].layout.b.file
assert(vim.bo[file.bufnr].modifiable)
vim.api.nvim_buf_set_lines(file.bufnr, 0, -1, false, {'edited index'})
vim.api.nvim_buf_set_mark(file.bufnr, '[', 1, 0, {})
vim.api.nvim_buf_set_mark(file.bufnr, ']', 1, 0, {})
vim.api.nvim_buf_call(file.bufnr, function() vim.cmd('write') end)
'''
                probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
                    'staged:' + name: dict(a=['base'], b=['staged'])})], extra, mutation_repo=repo.path)
                self.assertEqual(repo.git('show', ':' + name), 'edited index')
                self.assertEqual(repo.git('rev-parse', ':file-other'), unrelated)
                self.assertEqual((repo.path / name).read_text(), 'staged\n')

    def test_staged_review_stage_all_does_not_include_unrepresented_worktree_edits(self):
        repo = Repo(self.root / 'cached stage no-op')
        repo.write('selected', 'base\n')
        repo.commit()
        repo.write('selected', 'index\n')
        repo.git('add', '--', 'selected')
        repo.write('selected', 'worktree\n')
        before = repo.snapshot()
        self.mutate(repo, 'staged', ['selected'], {
            'working:selected': dict(a=['base'], b=['index'])}, 'S')
        self.assertEqual(repo.snapshot(), before)

    def test_untracked_restore_removes_only_the_selected_literal_file(self):
        repo = Repo(self.root / 'untracked restore')
        repo.write('base', 'base\n')
        repo.commit()
        repo.write('literal*', 'selected\n')
        repo.write('literal-other', 'preserved\n')
        self.mutate(repo, 'untracked', ['literal*'], {
            'working:literal*': dict(a=[''], b=['selected'])}, 'X')
        self.assertFalse((repo.path / 'literal*').exists())
        self.assertEqual((repo.path / 'literal-other').read_text(), 'preserved\n')

    def test_conflict_restore_refuses_an_ambiguous_index_without_mutating_it(self):
        repo = Repo(self.root / 'conflict restore')
        repo.write('file', 'base\n')
        repo.commit()
        repo.git('checkout', '-qb', 'side')
        repo.write('file', 'theirs\n')
        repo.commit()
        repo.git('checkout', '-q', 'main')
        repo.write('file', 'ours\n')
        repo.commit()
        repo.git('merge', 'side', check=False)
        self.assertIn('UU file', repo.git('status', '--porcelain'))
        before = repo.snapshot()
        self.mutate(repo, 'conflicted', ['file'], {'conflicting:file': {}}, 'X')
        self.assertEqual(repo.snapshot(), before)

    def test_sha256_dropped_stash_includes_saved_untracked_without_writes(self):
        repo = Repo(self.root / 'sha256 stash', object_format='sha256')
        repo.write('file', 'base\n')
        repo.commit()
        repo.write('file', 'saved index\n')
        repo.git('add', '--', 'file')
        repo.write('file', 'saved worktree\n')
        repo.write('untracked', 'saved untracked\n')
        repo.git('stash', 'push', '-qu')
        oid = repo.git('rev-parse', 'refs/stash')
        repo.git('stash', 'drop', '-q')
        spec = repo.spec('stash', stash_oid=oid)
        before = repo.snapshot()
        probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], readonly=True, contents={
            'working:file': dict(a=['base'], b=['saved worktree']),
            'staged:file': dict(a=['base'], b=['saved index']),
            'working:untracked': dict(a=[''], b=['saved untracked']),
        })])
        self.assertEqual(repo.snapshot(), before)

    def test_symlink_restore_and_undo_never_store_external_target_contents(self):
        sentinel = self.root / 'external-private-file'
        sentinel.write_bytes(b'EXTERNAL SENTINEL: never store this content\x00\xff')
        external_dir = self.root / 'external-directory'
        external_dir.mkdir()
        outside = sentinel.read_bytes(), sentinel.stat().st_mtime_ns
        for target in (sentinel, external_dir, self.root / 'missing-target'):
            for tracked in (False, True):
                with self.subTest(target=target.name, tracked=tracked):
                    repo = Repo(self.root / ('link-restore-' + str(len(list(self.root.iterdir())))))
                    repo.write('base', 'base\n')
                    link = repo.path / 'link*\n[ab]'
                    if tracked:
                        link.symlink_to('original-target')
                    repo.commit()
                    if tracked:
                        link.unlink()
                    link.symlink_to(target)
                    secret_oid = repo.git('hash-object', str(sentinel))
                    index = repo.git('ls-files', '--stage', '-z')
                    spec = repo.spec('diff', state='unstaged' if tracked else 'untracked',
                                     paths_b64=[b64(link.name)])
                    extra = '''
local view = require('diffview.lib').views[1]
local async = require('diffview.async')
local original = view.adapter.file_restore
local undo
view.adapter.file_restore = async.wrap(function(self, path, kind, commit, callback)
  local ok, command = async.await(original(self, path, kind, commit))
  undo = command
  callback(ok, command)
end)
view.panel:focus()
view.panel:set_cur_file(view.cur_entry)
view.panel:highlight_cur_file()
require('diffview.actions').restore_entry()
assert(vim.wait(5000, function() return undo ~= nil end, 10), 'restore did not return Undo')
local path = view.adapter.ctx.toplevel .. '/' .. view.cur_entry.path
''' + ("assert(vim.uv.fs_readlink(path) == 'original-target')\n" if tracked else
       "assert(vim.uv.fs_lstat(path) == nil)\n") + '''
vim.cmd(undo)
'''
                    probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
                        'working:' + link.name: dict(a=['original-target'] if tracked else [''], b=[str(target)])})],
                        extra, mutation_repo=repo.path)
                    self.assertTrue(link.is_symlink())
                    self.assertEqual(str(link.readlink()), str(target))
                    self.assertEqual(repo.git('ls-files', '--stage', '-z'), index)
                    found = subprocess.run(['git', '-C', str(repo.path), 'cat-file', '-e', secret_oid],
                                           capture_output=True, env=fixture_environment())
                    self.assertNotEqual(found.returncode, 0, 'external contents entered Git object storage')
                    self.assertEqual((sentinel.read_bytes(), sentinel.stat().st_mtime_ns), outside)

    def test_staged_rename_restore_and_undo_restore_both_endpoints_and_index(self):
        for file_kind in ('file', 'link', 'binary'):
            with self.subTest(file_kind=file_kind):
                repo = Repo(self.root / ('restore-rename-' + file_kind))
                old, new = 'from/old\n*', 'to/new\t[ab]'
                (repo.path / old).parent.mkdir()
                if file_kind == 'link':
                    (repo.path / old).symlink_to('missing-target')
                    text = 'missing-target'
                elif file_kind == 'binary':
                    repo.write(old, b'\x00\xffbinary data\n')
                else:
                    repo.write(old, 'rename contents\n')
                    (repo.path / old).chmod(0o755)
                    text = 'rename contents'
                repo.write('unrelated', 'base\n')
                repo.commit()
                (repo.path / new).parent.mkdir()
                repo.git('mv', '--', old, new)
                repo.write('unrelated', 'keep staged\n')
                repo.git('add', '--', 'unrelated')
                index = repo.git('ls-files', '--stage', '-z')
                spec = repo.spec('diff', paths_b64=[b64(old), b64(new)])
                extra = '''
local view = require('diffview.lib').views[1]
local async = require('diffview.async')
local original = view.adapter.file_restore
local undo
view.adapter.file_restore = async.wrap(function(self, path, kind, commit, callback)
  local ok, command = async.await(original(self, path, kind, commit))
  undo = command
  callback(ok, command)
end)
view.panel:focus()
view.panel:set_cur_file(view.files.staged[1])
view.panel:highlight_cur_file()
require('diffview.actions').restore_entry()
assert(vim.wait(5000, function() return undo ~= nil end, 10))
''' + 'local old = view.adapter.ctx.toplevel .. "/" .. vim.base64.decode(' + json.dumps(b64(old)) + ')\n' + \
      'local new = view.adapter.ctx.toplevel .. "/" .. vim.base64.decode(' + json.dumps(b64(new)) + ')\n' + '''
assert(vim.uv.fs_lstat(old) ~= nil and vim.uv.fs_lstat(new) == nil, 'rename endpoints not restored')
local result = vim.system({'git', '-C', view.adapter.ctx.toplevel, 'diff', '--cached', '--name-only'}):wait()
assert(result.stdout == 'unrelated\\n', 'rename left a staged deletion')
vim.cmd(undo)
'''
                expected = dict(binary=True, oldpath=old) if file_kind == 'binary' else dict(a=[text], b=[text], oldpath=old)
                probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
                    'staged:' + new: expected})], extra, mutation_repo=repo.path)
                self.assertEqual(repo.git('ls-files', '--stage', '-z'), index)
                self.assertFalse((repo.path / old).exists() or (repo.path / old).is_symlink())
                if file_kind == 'link':
                    self.assertEqual(str((repo.path / new).readlink()), text)
                elif file_kind == 'binary':
                    self.assertEqual((repo.path / new).read_bytes(), b'\x00\xffbinary data\n')
                else:
                    self.assertEqual((repo.path / new).read_text(), text + '\n')
                    self.assertEqual((repo.path / new).stat().st_mode & 0o777, 0o755)

    def test_sha256_unborn_staged_and_explicit_root_diff_use_correct_empty_tree(self):
        repo = Repo(self.root / 'sha256 ordinary diff', object_format='sha256')
        repo.write('file', 'root contents\n')
        repo.git('add', '--', 'file')
        spec = repo.spec('diff', state='staged', paths_b64=[b64('file')])
        before = repo.snapshot()
        probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], title='Staged [live]', contents={
            'working:file': dict(a=[''], b=['root contents'])})],
            gview_args=[str(repo.path), 'staged', '--', 'file'])
        self.assertEqual(repo.snapshot(), before)
        root = repo.commit()
        spec = repo.spec('diff', args=[root + '^!'])
        before = repo.snapshot()
        probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], title='Diff', readonly=True, contents={
            'working:file': dict(a=[''], b=['root contents'])})],
            gview_args=[str(repo.path), 'diff', root + '^!'])
        self.assertEqual(repo.snapshot(), before)

    def test_unborn_unstage_keeps_other_index_entries_on_both_object_formats(self):
        for object_format in ('sha1', 'sha256'):
            with self.subTest(object_format=object_format):
                repo = Repo(self.root / ('unborn unstage ' + object_format), object_format=object_format)
                for name in ('selected', 'unrelated'):
                    repo.write(name, 'index\n')
                repo.git('add', '-A')
                unrelated = repo.git('rev-parse', ':unrelated')
                self.mutate(repo, 'staged', ['selected'], {'working:selected': dict(a=[''], b=['index'])}, 'U')
                self.assertEqual(repo.git('ls-files'), 'unrelated')
                self.assertEqual(repo.git('rev-parse', ':unrelated'), unrelated)

    def test_undo_refuses_changed_symlink_parents_inside_and_outside_the_repo(self):
        for outside in (False, True):
            with self.subTest(outside=outside):
                repo = Repo(self.root / ('undo-parent-' + str(outside)))
                repo.write('from/file', 'base\n')
                repo.commit()
                repo.write('from/file', 'worktree\n')
                target = self.root / ('outside-' + str(outside)) if outside else repo.path / 'hidden'
                target.mkdir()
                (target / 'file').write_text('do not overwrite\n')
                index = repo.git('ls-files', '--stage', '-z')
                spec = repo.spec('diff', state='unstaged', paths_b64=[b64('from/file')])
                extra = '''
local view = require('diffview.lib').views[1]
local async = require('diffview.async')
local done, command = false, nil
async.void(function()
  local ok, undo = async.await(view.adapter:file_restore('from/file', 'working'))
  assert(ok)
  command, done = undo, true
end)()
assert(vim.wait(5000, function() return done end, 10))
local parent = view.adapter.ctx.toplevel .. '/from'
''' + 'assert(vim.uv.fs_rename(parent, ' + json.dumps(str(self.root / ('held-parent-' + str(outside)))) + '))\n' + \
      'assert(vim.uv.fs_symlink(' + json.dumps(str(target)) + ', parent))\n' + '''
local ok, err = pcall(vim.cmd, command)
assert(not ok and tostring(err):find('parent'), 'unsafe parent was accepted')
'''
                probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
                    'working:from/file': dict(a=['base'], b=['worktree'])})], extra, mutation_repo=repo.path)
                self.assertEqual((target / 'file').read_text(), 'do not overwrite\n')
                self.assertEqual(repo.git('ls-files', '--stage', '-z'), index)

    def test_restore_and_undo_refuse_new_index_descendants_before_any_write(self):
        for operation in ('restore', 'undo'):
            for object_format in ('sha1', 'sha256'):
                for name in ('selected', 'selected*\n[ab]', 'parent/selected'):
                    with self.subTest(operation=operation, object_format=object_format, path=name):
                        repo = Repo(self.root / ('restore-boundary-' + str(len(list(self.root.iterdir())))),
                                    object_format=object_format)
                        for path in (name, 'unrelated'):
                            repo.write(path, 'base\n')
                        base = repo.commit()
                        for path in (name, 'unrelated'):
                            repo.write(path, 'index\n')
                        repo.git('add', '-A')
                        repo.write(name, 'worktree\n')
                        spec = repo.spec('diff', args=[base], paths_b64=[b64(name)])
                        extra = '''
local view = require('diffview.lib').views[1]
local root, path = view.adapter.ctx.toplevel, vim.base64.decode(''' + json.dumps(b64(name)) + ''')
local operation = ''' + json.dumps(operation) + '''
local function git(args, input)
  local result = vim.system(vim.list_extend({'git', '--literal-pathspecs', '-C', root}, args), {stdin=input}):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout
end
local async = require('diffview.async')
local function restore()
  local done, success, command = false, nil, nil
  async.void(function()
    success, command = async.await(view.adapter:file_restore(path, 'working', view.left.commit))
    done = true
  end)()
  assert(vim.wait(5000, function() return done end, 10))
  return success, command
end
local command
if operation == 'undo' then
  local success
  success, command = restore()
  assert(success and command)
end
local oid = vim.trim(git({'rev-parse', ':unrelated'}))
git({'update-index', '--force-remove', '--', path})
local changed = path:find('/', 1, true) and path:match('^([^/]+)') or path .. '/hidden'
git({'update-index', '-z', '--index-info'}, '100644 ' .. oid .. ' 0\t' .. changed .. '\\0')
local index = vim.fn.readblob(root .. '/.git/index')
local work = vim.fn.readblob(root .. '/' .. path)
local objects = git({'cat-file', '--batch-all-objects', '--batch-check=%(objectname)'})
if operation == 'restore' then
  local utils, messages = require('diffview.utils'), {}
  local original = utils.err
  utils.err = function(message) messages[#messages + 1] = tostring(message) end
  local success = restore()
  utils.err = original
  assert(success == false, 'restore accepted undisplayed index descendants')
  assert(#messages > 0 and messages[1]:lower():find('refresh', 1, true))
else
  local ok, err = pcall(vim.cmd, command)
  assert(not ok and tostring(err):lower():find('refresh', 1, true), 'undo accepted undisplayed index descendants')
end
assert(vim.deep_equal(vim.fn.readblob(root .. '/.git/index'), index), 'refusal rewrote index')
assert(vim.deep_equal(vim.fn.readblob(root .. '/' .. path), work), 'refusal changed worktree')
assert(git({'cat-file', '--batch-all-objects', '--batch-check=%(objectname)'}) == objects, 'refusal wrote backup objects')
'''
                        probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
                            'working:' + name: dict(a=['base'], b=['worktree'])})],
                              extra, mutation_repo=repo.path)

    def test_restore_undo_preserves_intent_to_add_including_empty_and_missing_files(self):
        for object_format in ('sha1', 'sha256'):
            for kind in ('content', 'empty', 'removed', 'removed-link', 'sparse'):
                with self.subTest(object_format=object_format, kind=kind):
                    repo = Repo(self.root / ('ita-' + object_format + '-' + kind), object_format=object_format)
                    repo.write('base', 'base\n')
                    if kind == 'sparse':
                        repo.write('included/keep', 'included\n')
                    base = repo.commit()
                    if kind == 'sparse':
                        repo.git('sparse-checkout', 'set', '--cone', 'included')
                    repo.write('already-empty', '')
                    repo.git('add', '--', 'already-empty')
                    name = ('outside/' if kind == 'sparse' else '') + 'intent\n*?[ab]'
                    path = repo.path / name
                    if kind == 'removed-link':
                        path.symlink_to('missing-target')
                        expected = ['missing-target']
                    else:
                        repo.write(name, '' if kind == 'empty' else 'worktree\n')
                        expected = [''] if kind == 'empty' else ['worktree']
                    repo.git('add', '-N', '--sparse', '--', name)
                    index = repo.git('ls-files', '--stage', '-z')
                    cached = repo.git('diff', '--cached', '--raw', '-z')
                    spec = repo.spec('diff', args=[base], paths_b64=[b64(name)])
                    extra = 'local path = vim.base64.decode(' + json.dumps(b64(name)) + ')\n'
                    extra += '''
local view = require('diffview.lib').views[1]
local async = require('diffview.async')
'''
                    if kind.startswith('removed'):
                        extra += "assert(vim.uv.fs_unlink(view.adapter.ctx.toplevel .. '/' .. path))\n"
                    extra += '''
local done, command = false, nil
async.void(function()
  local ok, undo = async.await(view.adapter:file_restore(path, 'working', view.left.commit))
  assert(ok)
  command, done = undo, true
end)()
assert(vim.wait(5000, function() return done end, 10))
vim.cmd(command)
'''
                    probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
                        'working:' + name: dict(a=[''], b=expected)})], extra, mutation_repo=repo.path)
                    self.assertEqual(repo.git('ls-files', '--stage', '-z'), index)
                    self.assertEqual(repo.git('diff', '--cached', '--raw', '-z'), cached)
                    debug = repo.git('--literal-pathspecs', 'ls-files', '--debug', '-z', '--', name)
                    self.assertTrue(int(debug.rsplit('flags: ', 1)[1], 16) & 0x20000000)
                    if kind.startswith('removed'):
                        self.assertFalse(path.exists() or path.is_symlink())
                    else:
                        self.assertEqual(path.read_text(), '' if kind == 'empty' else 'worktree\n')

    def test_restore_undo_preserves_assume_unchanged_and_skip_worktree_flags(self):
        for assume, skip in ((True, False), (False, True), (True, True)):
            with self.subTest(assume=assume, skip=skip):
                repo = Repo(self.root / ('flags-' + str(assume) + '-' + str(skip)))
                repo.write('file', 'base\n')
                base = repo.commit()
                repo.write('file', 'index\n')
                repo.git('add', '--', 'file')
                repo.write('file', 'worktree\n')
                index = repo.git('ls-files', '--stage', '-z')
                spec = repo.spec('diff', args=[base], paths_b64=[b64('file')])
                extra = '''
local view = require('diffview.lib').views[1]
local async = require('diffview.async')
local flags = ''' + json.dumps(['--assume-unchanged' if assume else '--no-assume-unchanged',
                               '--skip-worktree' if skip else '--no-skip-worktree']).replace('[', '{').replace(']', '}') + '''
for _, flag in ipairs(flags) do
  assert(vim.system({'git', '-C', view.adapter.ctx.toplevel, 'update-index', flag, '--', 'file'}):wait().code == 0)
end
local done, command = false, nil
async.void(function()
  local ok, undo = async.await(view.adapter:file_restore('file', 'working', view.left.commit))
  assert(ok)
  command, done = undo, true
end)()
assert(vim.wait(5000, function() return done end, 10))
vim.cmd(command)
'''
                probe(self.root, [spec], [dict(repo_b64=spec['repo_b64'], contents={
                    'working:file': dict(a=['base'], b=['worktree'])})], extra, mutation_repo=repo.path)
                self.assertEqual(repo.git('ls-files', '--stage', '-z'), index)
                self.assertEqual((repo.path / 'file').read_text(), 'worktree\n')
                expected = 's' if assume and skip else 'S' if skip else 'h'
                self.assertEqual(repo.git('ls-files', '-v'), expected + ' file')


if __name__ == '__main__':
    unittest.main()
