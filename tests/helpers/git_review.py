"""Real disposable Git repositories and isolated production-Neovim review probes."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


CONFIG = Path(__file__).resolve().parents[2]


def b64(value):
    return base64.b64encode(os.fsencode(value)).decode('ascii')


def fixture_environment():
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null',
               GIT_NO_REPLACE_OBJECTS='1', GIT_OPTIONAL_LOCKS='0', GIT_TERMINAL_PROMPT='0')
    return env


class Repo:
    def __init__(self, path):
        self.path = path
        path.mkdir()
        self.git('init', '-q', '--initial-branch=main')
        if Path(self.git('rev-parse', '--show-toplevel')).resolve() != path.resolve():
            raise AssertionError('Fixture Git root differs from its temporary worktree')
        for key, value in [('user.name', 'Review fixture'),
                           ('user.email', 'fixture@example.invalid'),
                           ('commit.gpgsign', 'false'), ('core.hooksPath', '/dev/null')]:
            self.git('config', key, value)

    def git(self, *args, check=True):
        result = subprocess.run(['git', '-c', 'core.hooksPath=/dev/null', '-c', 'init.templateDir=',
                                 '-C', str(self.path), *args],
                                capture_output=True, check=check, env=fixture_environment())
        return result.stdout.decode(errors='surrogateescape').removesuffix('\n')

    def write(self, name, text):
        target = self.path / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(text if isinstance(text, bytes) else text.encode())

    def commit(self, message='Fixture'):
        self.git('add', '-A')
        self.git('commit', '-qm', message)
        return self.git('rev-parse', 'HEAD')

    def snapshot(self):
        # Compare actual bytes as well as Git's interpretation, including index,
        # refs, stash reflog, untracked files and symlink target text.
        status = self.git('--no-optional-locks', 'status', '--porcelain=v1', '-z')
        files = {}
        for path in self.path.rglob('*'):
            key = str(path.relative_to(self.path))
            if path.is_symlink():
                files[key] = ('link', os.readlink(path))
            elif path.is_file():
                files[key] = (path.stat().st_mode, path.read_bytes())
        return files, status, self.git('show-ref', check=False), self.git('stash', 'list')

    def spec(self, mode, title=None, **kwargs):
        spec = dict(mode=mode, repo_b64=b64(self.path), **kwargs)
        if title is not None:
            spec['title'] = title
        return spec


def probe(root, specs, expected, extra='', *, quit_key=False, gview_args=None):
    expected = [dict(item, contents_b64={b64(key): value for key, value
                in item.get('contents', {}).items()}, contents=None) for item in expected]
    script = root / 'probe.lua'
    script.write_text((CONFIG / 'tests/helpers/git_review_probe.lua').read_text())
    env = dict(fixture_environment(), LPKE_NVIM_NO_SESSION='1', LPKE_NVIM_DIFFVIEW_GIT_UI='1',
               LPKE_NVIM_DIFFVIEW_VIEWS=json.dumps(specs),
               LPKE_REVIEW_EXPECTED=json.dumps(expected), LPKE_REVIEW_EXTRA=extra,
               LPKE_REVIEW_QUIT='1' if quit_key else '',
               XDG_STATE_HOME=str(root / 'state'), XDG_CACHE_HOME=str(root / 'cache'))
    # Plugin downloads/runtime stay read-only in their installed location.
    command = [shutil.which('nvim'), '--headless', '-i', 'NONE', '-n',
               '-c', 'lua dofile(' + repr(str(script)) + ')']
    if gview_args is not None:
        binary = root / 'bin'
        binary.mkdir(exist_ok=True)
        wrapper = binary / 'nvim'
        wrapper.write_text('#!' + sys.executable + '\nimport os\nos.execv('
                           + repr(command[0]) + ', ' + repr(command) + ')\n')
        wrapper.chmod(0o755)
        env['PATH'] = str(binary) + os.pathsep + env['PATH']
        gview = Path(os.environ.get('GVIEW_SOURCE', str(Path.home()
                     / '.local/share/chezmoi/dot_local/bin/executable_gview')))
        command = [sys.executable, str(gview), *gview_args]
    result = subprocess.run(command,
                            cwd=root, env=env, capture_output=True,
                            text=True, errors='replace', timeout=40)
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'GIT_REVIEW_PASS' in result.stdout + result.stderr, result.stderr
    diagnostics = ''
    log = root / 'cache/nvim/diffview.log'
    if log.exists():
        diagnostics = log.read_text(errors='replace')[-8000:]
    for error in ('Error in ', 'vim.schedule callback:', 'Failed to create diff buffer'):
        assert error not in result.stdout + result.stderr, result.stderr + diagnostics
    return result
