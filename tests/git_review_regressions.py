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


if __name__ == '__main__':
    unittest.main()
