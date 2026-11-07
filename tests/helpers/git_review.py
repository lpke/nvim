"""Real disposable Git repositories and isolated production-Neovim review probes."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


CONFIG = Path(os.environ.get('GIT_REVIEW_NVIM_CONFIG', Path(__file__).resolve().parents[2])).resolve()


def b64(value):
    return base64.b64encode(os.fsencode(value)).decode('ascii')


def fixture_environment(source=None):
    env = {key: value for key, value in (os.environ if source is None else source).items() if not key.startswith('GIT_')}
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
                           ('commit.gpgsign', 'false'), ('core.hooksPath', '/dev/null'),
                           ('gc.auto', '0'), ('maintenance.auto', 'false')]:
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


# Copy code, never symlink installed plugin trees: Lazy/helptags and plugins may
# write alongside their code. All mutation destinations belong to this fixture.
PLUGINS = ('lazy.nvim', 'diffview.nvim', 'plenary.nvim', 'rose-pine',
           'auto-session', 'nvim-web-devicons', 'lualine.nvim')


def plugin_source():
    explicit = os.environ.get('GIT_REVIEW_NVIM_PLUGINS')
    candidates = [Path(explicit)] if explicit else [
        Path.home() / '.local/share/nvim/lazy',
        Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'nvim/lazy',
    ]
    for candidate in candidates:
        if all((candidate / name).is_dir() for name in PLUGINS):
            return candidate.resolve()
    raise AssertionError('Installed review plugins unavailable; set GIT_REVIEW_NVIM_PLUGINS: '
                         + ', '.join(map(str, candidates)))


def encode_expected(expected):
    result = []
    for item in expected:
        value = dict(item, contents_b64={b64(key): data for key, data
                     in item.get('contents', {}).items()}, contents=None)
        # Explicit ordered (commit,path) entries retain duplicate paths. Paths
        # travel as bytes, just like legacy contents and production view specs.
        if 'versions' in item:
            value['versions'] = [dict(entry, path_b64=b64(entry['path']), path=None)
                                 for entry in item['versions']]
        result.append(value)
    return result


class Harness:
    """One private production-config boot used by all three integration paths.

    Context-managed even on failed startup/timeouts. Original config/plugin code
    is read only by Python; Neovim sees independent copies, with no shared writable
    cache, lockfile, registry, sessions, home, runtime, or clipboard provider.
    """
    def __init__(self, root, script, env=None):
        self.parent = Path(root)
        self.parent.mkdir(parents=True, exist_ok=True)
        self.script = script
        self.inherited = fixture_environment() if env is None else dict(env)

    def __enter__(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='review-boot-', dir=str(self.parent))
        self.root = Path(self.temporary.name).resolve()
        try:
            plugins = plugin_source()
            self.config = self.root / 'config/nvim'
            ignore = shutil.ignore_patterns('.git', '__pycache__', '*.pyc')
            shutil.copytree(str(CONFIG), str(self.config), ignore=ignore, symlinks=False)
            for name in PLUGINS:
                shutil.copytree(str(plugins / name), str(self.root / 'data/nvim/lazy' / name),
                                ignore=ignore, symlinks=False)
            # Never inherit startup commands, runtime injections, provider homes,
            # app names, or review/session state from another running probe.
            env = fixture_environment(self.inherited)
            for key in list(env):
                if key.startswith(('XDG_', 'LPKE_', 'NVIM_', 'VIM')) or key in (
                        'LUA_PATH', 'LUA_CPATH', 'LUA_INIT', 'BASH_ENV', 'ENV', 'ZDOTDIR',
                        'SSH_CONNECTION', 'SSH_CLIENT', 'SSH_TTY', 'DISPLAY', 'WAYLAND_DISPLAY',
                        'DBUS_SESSION_BUS_ADDRESS'):
                    env.pop(key)
            env.update(HOME=str(self.root / 'home'), XDG_CONFIG_HOME=str(self.root / 'config'),
                       XDG_DATA_HOME=str(self.root / 'data'), XDG_CACHE_HOME=str(self.root / 'cache'),
                       XDG_STATE_HOME=str(self.root / 'state'), XDG_RUNTIME_DIR=str(self.root / 'runtime'),
                       TMPDIR=str(self.root / 'tmp'), NVIM_APPNAME='nvim',
                       LPKE_REVIEW_HARNESS=str(self.root), LPKE_REVIEW_SCRIPT=str(self.script),
                       LPKE_NVIM_NO_SESSION='1',
                       GIT_ALLOW_PROTOCOL='', GIT_CONFIG_GLOBAL=os.devnull,
                       GIT_CONFIG_SYSTEM=os.devnull, GIT_TERMINAL_PROMPT='0',
                       GIT_NO_LAZY_FETCH='1')
            for name in ('home', 'cache', 'state', 'runtime', 'tmp'):
                (self.root / name).mkdir(mode=0o700)
            self.env = env
            self.nvim = shutil.which('nvim')
            assert self.nvim, 'production Neovim unavailable'
            boot = self.config / 'tests/helpers/git_review_boot.lua'
            self.command = [self.nvim, '--headless', '-i', 'NONE', '-n', '-u', str(boot),
                            '-c', 'lua dofile(vim.env.LPKE_REVIEW_SCRIPT)']
            return self
        except BaseException:
            self.temporary.cleanup()
            raise

    def __exit__(self, *args):
        self.temporary.cleanup()

    def run(self, *, extra_env=None, gview_args=None, gview=None, marker='GIT_REVIEW_PASS', cwd=None):
        env = dict(self.env, **(extra_env or {}))
        command = self.command
        if gview_args is not None:
            binary = self.root / 'bin'
            binary.mkdir()
            wrapper = binary / 'nvim'
            wrapper.write_text('#!' + sys.executable + '\nimport os\nos.execv('
                               + repr(self.nvim) + ', ' + repr(command) + ')\n')
            wrapper.chmod(0o755)
            env['PATH'] = str(binary) + os.pathsep + env['PATH']
            gview = gview or Path(os.environ.get('GVIEW_SOURCE', str(Path.home()
                         / '.local/share/chezmoi/dot_local/bin/executable_gview')))
            command = [sys.executable, str(gview), *gview_args]
        result = subprocess.run(command, cwd=cwd or self.parent, env=env, capture_output=True,
                                text=True, errors='replace', timeout=50)
        diagnostics = ''
        log = self.root / 'cache/nvim/diffview.log'
        if log.exists():
            diagnostics = log.read_text(errors='replace')[-8000:]
        output = result.stdout + result.stderr
        assert result.returncode == 0, output + diagnostics
        assert marker in output, output + diagnostics
        for error in ('Error in ', 'vim.schedule callback:', 'Failed to create diff buffer'):
            assert error not in output, output + diagnostics
        return result


def probe(root, specs, expected, extra='', *, quit_key=False, gview_args=None, gview=None):
    script = CONFIG / 'tests/helpers/git_review_probe.lua'
    with Harness(root, script) as harness:
        return harness.run(extra_env=dict(
            LPKE_NVIM_DIFFVIEW_GIT_UI='1', LPKE_NVIM_DIFFVIEW_VIEWS=json.dumps(specs),
            LPKE_REVIEW_EXPECTED=json.dumps(encode_expected(expected)), LPKE_REVIEW_EXTRA=extra,
            LPKE_REVIEW_QUIT='1' if quit_key else ''), gview_args=gview_args, gview=gview)
