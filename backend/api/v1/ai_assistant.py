"""
Forum AI assistant.

Design intent (see conversation with the team): the assistant is NOT a
normal poster. It never starts organic threads on its own, never replies
unprompted, and never impersonates a human. It only speaks when a
moderator explicitly invokes it — either to draft a reply on a specific
post, or to draft a discussion-starter post inside a thread (e.g. a
weekly reflection prompt). Every piece of text it produces is persisted
under a dedicated, clearly-badged service account (see
get_or_create_bot_user in forums.py / models.User.is_bot) so nothing it
says is ever visually confusable with a real community member.

This module only knows how to call the model and return text — it has
no opinion about *where* that text gets saved. That decision (new post
vs. comment) lives in forums.py.
"""
import os
import logging
import requests

logger = logging.getLogger(__name__)

ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"
MODEL = "claude-sonnet-4-6"

SYSTEM_PROMPT = (
    "You are the community assistant for a discussion forum inside a "
    "faith-based fellowship app. You are replying as a clearly-labeled "
    "AI account, invoked on purpose by a moderator — never pretend to be "
    "a human member. Be warm, concise (3-6 sentences unless asked for "
    "more), and encourage the human community to keep talking to each "
    "other rather than treating you as the final word. Do not fabricate "
    "facts, citations, or scripture references you are not confident in — "
    "say so plainly if unsure instead. Avoid taking a side on divisive "
    "theological or political debates; offer perspective, not verdicts."
)


class AssistantError(Exception):
    """Raised when the assistant can't produce a reply (missing key, API
    failure, etc.) so the caller can turn it into a clean error_response."""


def _api_key() -> str | None:
    return os.getenv("ANTHROPIC_API_KEY")


def generate_assistant_reply(*, context: str, instruction: str, max_tokens: int = 600) -> str:
    """
    context: the thread/post/comment text the assistant is responding to,
        already trimmed to a reasonable size by the caller.
    instruction: what the moderator asked for, e.g. "Reply to this post"
        or "Write a short weekly reflection prompt about patience".
    """
    api_key = _api_key()
    if not api_key:
        raise AssistantError(
            "The AI assistant isn't configured yet — ask an admin to set "
            "the ANTHROPIC_API_KEY environment variable."
        )

    user_content = instruction
    if context:
        user_content += f"\n\n---\nForum context:\n{context}"

    try:
        resp = requests.post(
            ANTHROPIC_API_URL,
            headers={
                "x-api-key": api_key,
                "anthropic-version": ANTHROPIC_VERSION,
                "content-type": "application/json",
            },
            json={
                "model": MODEL,
                "max_tokens": max_tokens,
                "system": SYSTEM_PROMPT,
                "messages": [{"role": "user", "content": user_content}],
            },
            timeout=30,
        )
    except requests.RequestException as e:
        logger.error(f"Assistant request failed: {e}")
        raise AssistantError("Couldn't reach the AI assistant. Try again shortly.")

    if resp.status_code != 200:
        logger.error(f"Assistant API error {resp.status_code}: {resp.text}")
        raise AssistantError("The AI assistant couldn't generate a reply right now.")

    data = resp.json()
    text_parts = [
        block.get("text", "") for block in data.get("content", []) if block.get("type") == "text"
    ]
    text = "\n".join(p for p in text_parts if p).strip()
    if not text:
        raise AssistantError("The AI assistant returned an empty reply.")
    return text