"""Real-repository regression tests using the shared isolated Neovim harness.

Run: python3 tests/git_review_regressions.py
Only explicitly opted-in temporary repositories permit add/reset commands.
"""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
from helpers.git_review import Harness, Repo, b64, probe


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


if __name__ == '__main__':
    unittest.main()
