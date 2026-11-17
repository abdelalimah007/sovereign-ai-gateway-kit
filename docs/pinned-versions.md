# Pinned versions

Resolved and verified on **2026-11-16**. Every container image digest below is
the **multi-arch index** digest (OCI image index with `linux/amd64` and
`linux/arm64`), so the same pin works on Apple Silicon and x86. Resolved with
`docker buildx imagetools inspect <name:tag>`, then pulled by digest and run.

## Container images

| Component | Image | Version | Digest (index) |
|---|---|---|---|
| Gateway | `ghcr.io/berriai/litellm-non_root` | v1.109.1 | `sha256:e9e15fe17b66fc8cda6ff7e18914e1d452785ca404fa20336ec447152f86daba` |
| Model runtime + model-init | `ollama/ollama` | 0.40.16 | `sha256:910d0d8107b538fb0894e63163eb195de0cc7aefcbc666dc62d3b18f71124592` |
| PII analyzer | `mcr.microsoft.com/presidio-analyzer` | 2.2.362 | `sha256:286e3fa7f3a7426e775e8564fe1870f1ba8f999d3ab8bbb8cc46a44355d9d6e9` |
| PII anonymizer | `mcr.microsoft.com/presidio-anonymizer` | 2.2.362 | `sha256:a10a12a2a613d13cf29d3ad3641e3258444dd8c90403dd644a0a114c472c2483` |
| `tap` base + `ingress` | `python` | 3.14.10-slim-trixie | `sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f` |
| verify.sh: shellcheck | `koalaman/shellcheck` | v0.11.0 | `sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d` |
| verify.sh: gitleaks | `ghcr.io/gitleaks/gitleaks` | v8.30.1 | `sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f` |

Notes on the choices:

- **LiteLLM v1.109.1** was the newest *stable* release on 2026-11-16 (GitHub
  release, not a pre-release). At that date 1.110.0 was still a release
  candidate, and 1.108.x was the LTS line. LiteLLM's release-cycle page says to
  "pin to the latest stable 1.x.x release". It is long after the March 2026
  incident (first clean release after it: v1.83.0). The `litellm-non_root`
  variant is published by the same project in the same registry and runs as
  UID 65534. The version in the running container is checked by
  `scripts/verify.sh` (`importlib.metadata.version('litellm')` returns `1.109.1`).
  LiteLLM also signs its images: the release notes give a `cosign verify` command
  with a pinned public key.
- **Presidio 2.2.362** is the newest version *published on MCR* on 2026-11-16.
  GitHub has releases up to 2.2.366, but MCR has no images for them. On that
  date, `:latest` resolved to the same digest as `2.2.362`. The analyzer ships
  spaCy 3.8.11 with `en_core_web_lg` 3.8.0 (English only) and listens on port
  3000, with health on `/health`.
- **Ollama 0.40.16** was the newest stable release (0.40.17 was an rc).

## Models (Ollama library)

Ollama 0.40.16 does not accept `name@sha256:...` in `ollama pull` ("invalid
model name"). So `scripts/pull-models.sh` pulls by tag and then verifies the
**manifest digest**: `ollama list` must show it for the tag, and the stored copy
of the registry manifest (`blobs/sha256-<digest>`) must hash to it. On mismatch
the model is removed and `model-init` fails.

| Alias | Model | Manifest digest | Size | Licence |
|---|---|---|---|---|
| reasoning (stand-in) | `granite4:3b` | `sha256:89962fcc75239ac434cdebceb6b7e0669397f92eaef9c487774b718bc36a3e5f` | 2.10 GB | Apache-2.0 |
| code | `qwen2.5-coder:1.5b` | `sha256:d7372fd828518a4d38b1eb196c673c31a85f2ed302b3d1e406c4c2d1b64a0668` | 0.99 GB | Apache-2.0 |
| fast | `qwen2.5:1.5b-instruct` | `sha256:65ec06548149b04c096a120e4a6da9d4017ea809c91734ea5631e89f96ddc57b` | 0.99 GB | Apache-2.0 |
| embed | `nomic-embed-text:v1.5` | `sha256:0a109f422b47e3a30ba2b10eca18548e944e8a23073ee3f3e947efcf3c45e59f` | 0.27 GB | Apache-2.0 |

Digests were read from `https://registry.ollama.ai/v2/library/<name>/manifests/<tag>`.
Sizes are the sum of the manifest layers. The licences were read from each
model's licence layer. `qwen2.5:3b` (Qwen Research License, non-commercial) and
`llama3.2:3b` (Llama 3.2 Community License) were considered for `reasoning`
and not used because of their licences.

## How to update a pin safely

1. Read the project's release notes and security advisories for the new version.
   For LiteLLM, never use 1.82.7 or 1.82.8, and do not use `latest`, `main-*`,
   `-dev`, `-rc` or `-nightly` tags.
2. Resolve the index digest for the exact version tag:
   `docker buildx imagetools inspect ghcr.io/berriai/litellm-non_root:v<X.Y.Z>`.
   Check that the index lists both `linux/amd64` and `linux/arm64`.
3. Optionally verify the signature (LiteLLM: the `cosign verify` command in the
   release notes).
4. Change `name:tag@sha256:<digest>` in `docker-compose.yml` (or the `FROM` line),
   and update this file.
5. For a model, read the new manifest digest from the registry URL above, update
   `MODELS` in `scripts/pull-models.sh`, and run `docker compose up -d` (model-init
   checks it).
6. Run `./scripts/verify.sh` and `./test-prompts.sh --with-fallback`. Config keys can
   change between LiteLLM versions. The running image wins over the docs.
