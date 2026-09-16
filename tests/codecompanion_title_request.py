"""python tests/codecompanion_title_request.py
Capture a real Codex request through the Neovim helper, using a local fake API.
No real model request or credentials are sent. Requires nvim and codex on PATH.
"""
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading

repo = Path(__file__).resolve().parents[1]
prompt = 'Explain Lua table iteration, café, and $(literal shell text).'
requests = []
status = 200


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        data = self.rfile.read(int(self.headers['Content-Length']))
        assert not self.headers.get('Content-Encoding'), 'Unexpected compressed request'
        requests.append(json.loads(data))
        self.send_response(status)
        if status != 200:
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"error":{"message":"Fixture unavailable","type":"server_error"}}')
            return
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        message = {
            'id': 'msg_fixture', 'type': 'message', 'role': 'assistant',
            'status': 'completed',
            'content': [{'type': 'output_text', 'text': 'Lua Table Iteration'}],
        }
        events = [
            {'type': 'response.created', 'response': {'id': 'resp_fixture'}},
            {'type': 'response.output_item.added', 'output_index': 0, 'item': message},
            {'type': 'response.output_item.done', 'output_index': 0, 'item': message},
            {'type': 'response.completed', 'response': {
                'id': 'resp_fixture', 'object': 'response', 'status': 'completed',
                'output': [message],
                'usage': {'input_tokens': 20, 'output_tokens': 4, 'total_tokens': 24},
            }},
        ]
        for event in events:
            self.wfile.write(('data: ' + json.dumps(event) + '\n\n').encode())
            self.wfile.flush()


with tempfile.TemporaryDirectory(prefix='lpke-title-test-') as temp:
    root = Path(temp)
    auth = root / 'original-codex'
    auth.mkdir()
    (auth / 'auth.json').write_text('{}')
    (auth / 'AGENTS.md').write_text('LEAK_GLOBAL_AGENTS')
    (auth / 'config.toml').write_text('developer_instructions = "LEAK_USER_CONFIG"')
    project = root / 'project'
    project.mkdir()
    (project / 'AGENTS.md').write_text('LEAK_PROJECT_AGENTS')
    skill = auth / 'skills' / 'fixture'
    skill.mkdir(parents=True)
    (skill / 'SKILL.md').write_text('---\nname: leaked-skill\ndescription: LEAK_SKILL\n---\nLEAK_SKILL')
    server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    script = root / 'request.lua'
    script.write_text(r'''
vim.opt.rtp:prepend(vim.env.LPKE_TITLE_TEST_REPO)
local system = vim.system
local workdir
local expect_failure = vim.env.LPKE_TITLE_TEST_FAIL ~= nil
vim.system = function(command, opts, callback)
  workdir = opts.cwd
  assert(opts.env.CODEX_HOME ~= vim.env.CODEX_HOME)
  assert(opts.env.CODEX_CONFIG_FILE == false)
  assert(vim.uv.fs_lstat(opts.env.CODEX_HOME .. '/auth.json').type == 'link')
  table.remove(command) -- stdin marker
  vim.list_extend(command, {
    '-c', 'features.enable_request_compression=false',
    '-c', 'model_providers.lpke_title.base_url="http://127.0.0.1:'
      .. vim.env.LPKE_TITLE_TEST_PORT .. '/v1"',
    '-c', 'model_providers.lpke_title.requires_openai_auth=false',
    '-',
  })
  return system(command, opts, function(result)
    if result.code ~= 0 and not expect_failure then
      io.stderr:write(result.stderr or '')
    end
    callback(result)
  end)
end
local done, title = false, nil
require('lpke.plugins.ai.helpers.title_request').request(vim.env.LPKE_TITLE_TEST_PROMPT, function(value)
  done, title = true, value
end)
assert(vim.wait(35000, function() return done end), 'Codex title process timed out')
if expect_failure then
  assert(title == nil, 'Failed request returned a title')
else
  assert(title == 'Lua Table Iteration', 'Unexpected title: ' .. tostring(title))
end
assert(vim.fn.isdirectory(workdir) == 0, 'Title request left temporary files')
''')
    env = os.environ | {
        'CODEX_HOME': str(auth), 'CODEX_CONFIG_FILE': str(auth / 'config.toml'),
        'LPKE_TITLE_TEST_REPO': str(repo), 'LPKE_TITLE_TEST_PORT': str(server.server_port),
        'LPKE_TITLE_TEST_PROMPT': prompt,
    }
    try:
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-l', str(script)],
                                cwd=project, env=env, text=True, capture_output=True, timeout=45)
        assert result.returncode == 0, result.stdout + result.stderr
        assert len(requests) == 1, f'Expected one request, got {len(requests)}'
        request = requests[0]
        assert request['model'] == 'gpt-5.6-luna'
        assert request['reasoning']['effort'] == 'low'
        messages = [item for item in request['input'] if item['type'] == 'message']
        assert [item['role'] for item in messages] == ['developer', 'user'], messages
        assert messages[-1]['content'] == [{'type': 'input_text', 'text': prompt}]
        assert 'Write a concise chat title' in messages[0]['content'][0]['text']
        serialized = json.dumps(request)
        for forbidden in ['LEAK_', 'AGENTS.md', '<environment_context>', '<skills_instructions>',
                          '<permissions instructions>', '<collaboration_mode>']:
            assert forbidden not in serialized, f'Unexpected context: {forbidden}'
        assert (auth / 'auth.json').read_text() == '{}'
        assert not (auth / 'sessions').exists(), 'Created a persisted Codex session'
        print('PASS: one Luna/low request, exact prompt, no inherited instructions/skills/environment, temporary files removed')
        requests.clear()
        status = 503
        env['LPKE_TITLE_TEST_FAIL'] = '1'
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-l', str(script)],
                                cwd=project, env=env, text=True, capture_output=True, timeout=45)
        assert result.returncode == 0, result.stdout + result.stderr
        assert len(requests) == 1, f'Failed title request retried {len(requests)} times'
        print('PASS: real Codex HTTP failure settled without retrying and removed temporary files')
    finally:
        server.shutdown()
        server.server_close()
