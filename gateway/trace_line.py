"""One JSON trace line per model call: metadata only, never prompt or response text.

Loaded by config.yaml (litellm_settings.callbacks). It prints to stdout, so the
line ends up in `docker compose logs litellm` and nowhere else.
"""
import json
import sys

from litellm.integrations.custom_logger import CustomLogger


class TraceLine(CustomLogger):
    def _emit(self, kwargs, status):
        p = kwargs.get("standard_logging_object") or {}
        meta = p.get("metadata") or {}
        line = {
            "event": "llm_call",
            "status": status,
            "alias": p.get("model_group"),
            "model": p.get("model"),
            "api_base": p.get("api_base"),
            "tags": p.get("request_tags"),
            "guardrails": meta.get("applied_guardrails"),
            "prompt_tokens": p.get("prompt_tokens"),
            "completion_tokens": p.get("completion_tokens"),
            "latency_ms": round(1000 * (p.get("response_time") or 0)),
            "stream": bool(p.get("stream")),
            "call_id": p.get("litellm_call_id"),
        }
        if status == "failure":  # error class only: provider messages can quote the prompt
            line["error"] = ((p.get("error_information") or {}).get("error_class")) or "unknown"
        print(json.dumps(line), file=sys.stdout, flush=True)

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        self._emit(kwargs, "success")

    async def async_log_failure_event(self, kwargs, response_obj, start_time, end_time):
        self._emit(kwargs, "failure")


trace_line = TraceLine()
