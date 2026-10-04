"""Small, fail-closed evaluator for the Actions expressions used by policy tests.

These tests evaluate the checked-in YAML, not a duplicate eligibility/concurrency
policy. This is deliberately not a general Actions runner; unknown syntax fails.
"""

from __future__ import annotations

import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[3]
EXPRESSION = re.compile(r"\$\{\{(.*?)\}\}", re.DOTALL)
TOKEN = re.compile(r"\s*(\|\||&&|==|!=|[!(),]|'[^']*'|[\w.-]+)")


def workflow(name: str) -> dict:
    # BaseLoader preserves 'on' as a key and keeps boolean scalars predictable.
    return yaml.load((ROOT / ".github/workflows" / name).read_text(), Loader=yaml.BaseLoader)


def evaluate(expression: str, context: dict):
    expression = expression.strip()
    if expression.startswith("${{"):
        expression = EXPRESSION.fullmatch(expression).group(1).strip()
    tokens = []
    position = 0
    while position < len(expression):
        match = TOKEN.match(expression, position)
        if not match:
            raise AssertionError(f"Unsupported expression: {expression[position:]}")
        tokens.append(match.group(1))
        position = match.end()
    index = 0

    def atom():
        nonlocal index
        token = tokens[index]
        index += 1
        if token == "!":
            return not atom()
        if token == "(":
            value = binary(0)
            assert tokens[index] == ")"
            index += 1
            return value
        if token.startswith("'"):
            return token[1:-1]
        if token in ("true", "false"):
            return token == "true"
        if token == "startsWith":
            assert tokens[index] == "("
            index += 1
            value = binary(0)
            assert tokens[index] == ","
            index += 1
            prefix = binary(0)
            assert tokens[index] == ")"
            index += 1
            return str(value).startswith(prefix)
        value = context
        for key in token.split("."):
            value = value.get(key, "") if isinstance(value, dict) else ""
        return value

    def binary(level):
        nonlocal index
        operators = (("||",), ("&&",), ("==", "!="))
        if level == len(operators):
            return atom()
        value = binary(level + 1)
        while index < len(tokens) and tokens[index] in operators[level]:
            operator = tokens[index]
            index += 1
            right = binary(level + 1)
            if operator == "||":
                value = value or right
            elif operator == "&&":
                value = value and right
            elif operator == "==":
                value = value == right
            else:
                value = value != right
        return value

    value = binary(0)
    assert index == len(tokens), f"Unused expression tokens: {tokens[index:]}"
    return value


def render(value: str, context: dict) -> str:
    def replacement(match):
        result = evaluate(match.group(1), context)
        return str(result).lower() if isinstance(result, bool) else str(result)

    return EXPRESSION.sub(replacement, value)


def permitted(job: dict, context: dict) -> bool:
    # A job with no explicit condition is eligible when its dependencies succeed.
    return bool(evaluate(job["if"], context)) if "if" in job else True


def context(name: str, event="workflow_dispatch", tag="", author="human", release_tag=""):
    return {
        "github": {
            "workflow": name,
            "event_name": event,
            "ref": "refs/heads/main" if event == "workflow_dispatch" else f"refs/tags/{tag}",
            "sha": "dispatch-sha",
            "run_id": "123",
            "event": {"release": {"tag_name": tag, "author": {"login": author, "type": "Bot" if author.endswith("[bot]") else "User"}},
                      "inputs": {"release_tag": release_tag}},
        },
        "inputs": {"release_tag": release_tag},
    }
