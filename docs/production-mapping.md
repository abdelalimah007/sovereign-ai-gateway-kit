# Mapping to production

On a laptop, all four aliases hit small local models. The kit shows the
**pattern** (alias, route, guardrail, fallback), not production quality or
capacity. Model names are examples of each class, not recommendations.

| Alias | What runs in the kit | What it would be in the talk's reference architecture | What changes |
|---|---|---|---|
| `reasoning` | `granite4:3b` (~3B, CPU) behind `tap`, which records what a remote model receives | A large long-context model on a sovereign GPU cloud such as MeluXina. It is remote, so requests are pseudonymised first. | `api_base` (one line, via `REASONING_API_BASE`), plus `REASONING_MODEL` and a key |
| `code` | `qwen2.5-coder:1.5b` on Ollama | A code model on-prem behind vLLM or similar | `model`, `api_base` |
| `fast` | `qwen2.5:1.5b-instruct` on Ollama | A small fast model on-prem for high-volume classification and extraction | `model`, `api_base` |
| `embed` | `nomic-embed-text:v1.5` (768 dims) on Ollama | An on-prem embedding model feeding a vector store | `model`, `api_base` |

## What is deliberately not in the kit

- **The guard model** shown on the talk's slides 12 and 14 (a small model that
  classifies every prompt). On a CPU laptop it would add another model call to
  every request. The kit uses LiteLLM's built-in content filter (regex and keyword
  lists) and Presidio instead. They are cheaper and weaker.
- **Step 4 "filter out"** (checks on the model's answer) is not configured.
- **Virtual keys, budgets, quotas, spend logs and a database.** These need
  LiteLLM with Postgres. Attaching guardrails or policies to specific teams or
  keys is a LiteLLM Enterprise feature. The kit uses `default_on: true`, which
  applies both guardrails to every request.
- **Capacity**: one request at a time per model (`OLLAMA_NUM_PARALLEL=1`), at most
  two models loaded, 4k context.
- **Routing on context size** (for example sending long documents to
  `reasoning`) is not shown. The caller picks the alias.
