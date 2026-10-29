"""Local ACP peer for transport regression tests. It never contacts an AI service."""

import json
import os
import sys
import time

log_path = sys.argv[1]
profile = sys.argv[2] if len(sys.argv) > 2 else "normal"
options = [
    {
        "id": "model",
        "category": "model",
        "name": "Model",
        "type": "select",
        "currentValue": "other",
        "options": [
            {"value": "other", "name": "Other"},
            {"value": "gpt-6.1-sol", "name": "Sol"},
        ],
    },
    {
        "id": "mode",
        "category": "mode",
        "name": "Mode",
        "type": "select",
        "currentValue": "default",
        "options": [
            {"value": "default", "name": "Default"},
            {"value": "full-access", "name": "Full Access"},
        ],
    },
    {
        "id": "thought_level",
        "category": "thought_level",
        "name": "Reasoning",
        "type": "select",
        "currentValue": "low",
        "options": [{"value": "low", "name": "Low"}, {"value": "high", "name": "High"}],
    },
]


def record(value):
    with open(log_path, "a") as log:
        log.write(json.dumps(value) + "\n")


def send(value):
    encoded = json.dumps({"jsonrpc": "2.0", **value}) + "\n"
    sys.stdout.write(encoded[:11])
    sys.stdout.flush()
    sys.stdout.write(encoded[11:])
    sys.stdout.flush()


def update(session, kind, text):
    send(
        {
            "method": "session/update",
            "params": {
                "sessionId": session,
                "update": {
                    "sessionUpdate": kind,
                    "content": {"type": "text", "text": text},
                },
            },
        }
    )


record(
    {
        "event": "spawn",
        "pid": os.getpid(),
        "config": os.environ.get("CODEX_CONFIG"),
        "cwd": os.getcwd(),
    }
)
for line in sys.stdin:
    message = json.loads(line)
    record(message)
    if "id" not in message or "method" not in message:
        continue
    method, params = message["method"], message.get("params", {})
    result = {}
    if method == "initialize":
        result = {
            "protocolVersion": params.get("protocolVersion", 1),
            "agentCapabilities": {
                "loadSession": True,
                "promptCapabilities": {"image": True},
            },
            "authMethods": [{"id": "chat-gpt", "name": "Fixture auth"}],
        }
        if profile == "no-load":
            result["agentCapabilities"]["loadSession"] = False
        elif profile == "missing-load":
            del result["agentCapabilities"]["loadSession"]
    elif method in ("session/new", "session/load"):
        if params.get("sessionId") == "missing-fixture-id":
            send(
                {
                    "id": message["id"],
                    "error": {"code": -32000, "message": "Fixture session missing"},
                }
            )
            continue
        if profile == "slow-load" and method == "session/load":
            update(params["sessionId"], "user_message_chunk", "Saved original prompt")
            update(params["sessionId"], "agent_message_chunk", "Saved original answer")
            time.sleep(0.2)
        result = {
            "sessionId": params.get("sessionId", "fixture-session"),
            "configOptions": options,
        }
    elif method == "session/set_config_option":
        if profile.startswith("slow-"):
            time.sleep(0.1)
        for option in options:
            if option["id"] == params["configId"]:
                option["currentValue"] = params["value"]
        result = {"configOptions": options}
    elif method == "session/prompt":
        update(params["sessionId"], "agent_thought_chunk", "Fixture reasoning")
        update(params["sessionId"], "agent_message_chunk", "Fixture reply")
        result = {"stopReason": "end_turn"}
    send({"id": message["id"], "result": result})
