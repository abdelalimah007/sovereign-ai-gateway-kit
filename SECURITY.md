# Security

This is a learning kit, not a production system. Do not put real personal data,
secrets or client data into it.

## Reporting a problem

Please use GitHub's private vulnerability reporting on this repository
("Security" tab, then "Report a vulnerability"). Do not open a public issue for
a security problem. Plain bugs can go in normal issues.

## Supply chain

- **Every image is pinned by version and digest** (`name:tag@sha256:...`), and the
  `tap` Dockerfile's base image too. `scripts/verify.sh` fails on any `image:` or
  `FROM` line without a digest. Details and the update procedure:
  [docs/pinned-versions.md](docs/pinned-versions.md).
- **Models are pinned by manifest digest.** `scripts/pull-models.sh` pulls by tag
  (Ollama 0.40.16 refuses to pull by digest), then checks the digest and removes
  the model again if it does not match.
- **LiteLLM 1.82.7 and 1.82.8 are excluded.** These two PyPI releases were
  compromised on 24 March 2026. The entry point was a compromised security scanner
  (Trivy) in LiteLLM's CI/CD pipeline. 1.82.8 also shipped a `litellm_init.pth`
  file. Sources:
  - JFrog Security Research (24 Mar 2026), "Popular litellm Python package is the
    latest victim of TeamPCP's ongoing supply chain attack":
    <https://research.jfrog.com/post/litellm-compromised-teampcp/>
  - LiteLLM, "Security Update: Suspected Supply Chain Incident" (March 2026):
    <https://docs.litellm.ai/blog/security-update-march-2026>

  The kit uses the official proxy image, from a release after the incident
  (v1.109.1, built by the new pipeline). `scripts/verify.sh` reads the version
  from the running container. It fails on 1.82.7 or 1.82.8, on either string in
  a compose image tag, and on any `litellm_init.pth` in site-packages.
- **No runtime installs.** Nothing is installed with `pip` at startup. `tap` and the
  `ingress` relay use only the Python standard library.

## Network ("close the exits")

| Container | Networks | Route out |
|---|---|---|
| litellm, tap, ollama, presidio-analyzer, presidio-anonymizer | `internal` (`internal: true`) | none |
| ingress (TCP relay to litellm, publishes 127.0.0.1:4000) | `internal`, `edge` | yes, see below |
| model-init (one-shot, downloads models, then exits) | `egress` | yes, while it runs |

Docker cannot publish a port from a container that is only on an internal
network. So a 40-line standard-library relay (`ingress/relay.py`) sits on both
networks, and the gateway itself never gets a route out. The relay only opens
connections to `litellm:4000`. It is the one long-running container on a network
with a route out. A real deployment would put a hardened reverse proxy or the
platform's load balancer there.

`docker-compose.remote.yml` gives `litellm` a route out so `reasoning` can reach
a remote endpoint. Docker alone cannot limit that route to one host. For a true
allow-list, add an egress proxy or a firewall rule (see the comment in that file).

LiteLLM is also told not to make outbound requests of its own:
`LITELLM_OFFLINE_MODE=true` stops the cost-map fetch, the release check and the
tokenizer downloads, and `LITELLM_TELEMETRY_DISABLED=true` keeps usage telemetry
off. Ollama runs with `OLLAMA_NO_CLOUD=1`.

## Container hardening

All long-running services run with `cap_drop: [ALL]` and
`no-new-privileges:true`. All of them have a read-only root filesystem, with a
tmpfs on `/tmp` where needed.

- `litellm` uses the official `litellm-non_root` image (UID 65534) from the same
  registry, so the gateway does not run as root.
- `presidio-analyzer` logs one harmless line at start with a read-only root
  filesystem: `Control server error: [Errno 30] Read-only file system`. That is
  the web server's optional control socket. The service is healthy and answers
  normally.
- `ollama` runs as root inside its container (the image's default), with no
  capabilities and a read-only root. Only the `models` volume is writable.
- `model-init` is not read-only: it writes the models into the volume.

## Secrets

The only credential is a local master key in `.env` (git-ignored). The placeholder
in `.env.example` works, because the port is bound to 127.0.0.1 only. Generate
your own key anyway, and always before exposing the port (`openssl rand -hex 24`).
A key in an `.env` file on a laptop is a compromise. In production, use a secret
store or vault, and short-lived provider keys.

## The gateway is the crown jewel

Every prompt passes through it, it holds the provider keys, and it holds the
pseudonymisation map while a request is in flight. Treat it like the most
sensitive service you run: pinned, patched, monitored, and isolated.
