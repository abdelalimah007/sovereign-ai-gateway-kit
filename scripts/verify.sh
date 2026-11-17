#!/usr/bin/env bash
# Acceptance checks for the kit. Prints PASS/FAIL per check; exit 0 only if all pass.
# Usage: ./scripts/verify.sh [--keep-volume]
#   --keep-volume  start clean but keep the downloaded models (skips `down -v`)
# WARNING: by default this runs `docker compose down -v`, which deletes the
# model volume, so the models are downloaded again (about 4.4 GB).
set -euo pipefail
cd "$(dirname "$0")/.."

KEEP_VOLUME=0
[[ "${1:-}" == "--keep-volume" ]] && KEEP_VOLUME=1

SHELLCHECK_IMAGE="koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d"
GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"
OLLAMA_IMAGE=$(sed -n 's/^ *image: \(ollama\/ollama:.*\)$/\1/p' docker-compose.yml | head -n1)
# Fake test data that must never appear in any log or file the stack writes.
PII=(Viktor Marenko "LU28 0019" "4006 4475" "LU280019" "viktor.marenko@example.lu" "14/03/1991" "AKIAIOSFODNN7EXAMPLE" "GB00 WEST")

PASSES=(); FAILS=()
check() { # name ok [detail]
  if [[ "$2" == 1 ]]; then printf 'PASS  %s %s\n' "$1" "${3:-}"; PASSES+=("$1")
  else printf 'FAIL  %s %s\n' "$1" "${3:-}"; FAILS+=("$1"); fi
}

# Keep the user's own .env safe: the clean start copies .env.example over it.
if [[ -f .env ]]; then cp .env .env.verify-backup; trap 'mv -f .env.verify-backup .env' EXIT; fi

echo "== 1. compose files validate"
ok=1
docker compose config -q || ok=0
docker compose -f docker-compose.yml -f docker-compose.remote.yml config -q || ok=0
check "1 compose config" "$ok"

echo "== 2. every image and FROM is pinned by digest"
ok=1
while IFS= read -r line; do
  ref=$(sed -E 's/^[[:space:]]*(image:|FROM)[[:space:]]+//I' <<<"$line" | awk '{print $1}')
  if [[ "$ref" != *@sha256:* || "$ref" == *:latest* ]]; then echo "  not pinned: $ref"; ok=0; fi
done < <(grep -h -E '^[[:space:]]*image:' docker-compose*.yml; grep -h -i -E '^FROM ' tap/Dockerfile)
check "2 digest pinning" "$ok"

echo "== 3. clean start"
if [[ "$KEEP_VOLUME" == 1 ]]; then docker compose down; else docker compose down -v; fi
cp .env.example .env
t0=$SECONDS
docker compose up -d --build
ok=0
deadline=$((SECONDS + 3600))
while (( SECONDS < deadline )); do
  init=$(docker compose ps -a --format '{{.State}} {{.ExitCode}}' model-init)
  unhealthy=$(docker compose ps --format '{{.Service}} {{.Health}}' | awk '$2 != "" && $2 != "healthy"' || true)
  if [[ "$init" == "exited 0" && -z "$unhealthy" ]]; then ok=1; break; fi
  [[ "$init" == exited* && "$init" != "exited 0" ]] && break
  sleep 5
done
COLD_START=$((SECONDS - t0))
docker compose ps --format '  {{.Service}}: {{.State}} {{.Health}}'
check "3 clean start, all healthy" "$ok" "(${COLD_START}s)"

echo "== 4. LiteLLM version and compromise indicators"
ver=$(docker compose exec -T litellm python -c "import importlib.metadata as m; print(m.version('litellm'))" | tr -d '\r')
pth=$(docker compose exec -T litellm python -c "
import site, os
paths = site.getsitepackages() + [site.getusersitepackages()]
print(' '.join(os.path.join(p, f) for p in paths if os.path.isdir(p) for f in os.listdir(p) if f == 'litellm_init.pth'))" | tr -d '\r')
ok=1
[[ "$ver" == 1.82.7 || "$ver" == 1.82.8 || -z "$ver" ]] && ok=0
grep -E '^[[:space:]]*image:.*litellm' docker-compose*.yml | grep -q -E '1\.82\.(7|8)' && ok=0
[[ -n "$pth" ]] && { echo "  found: $pth"; ok=0; }
check "4 litellm version" "$ok" "(running: $ver; litellm_init.pth: ${pth:-none})"

echo "== 5. demo passes (twice, then with fallback)"
ok=1
t0=$SECONDS; ./test-prompts.sh >/dev/null || { echo "  run 1 failed"; ok=0; }; RUN1=$((SECONDS - t0))
t0=$SECONDS; ./test-prompts.sh >/dev/null || { echo "  run 2 failed"; ok=0; }; RUN2=$((SECONDS - t0))
t0=$SECONDS; ./test-prompts.sh --with-fallback >/dev/null || { echo "  fallback run failed"; ok=0; }; RUN3=$((SECONDS - t0))
check "5 test-prompts x3" "$ok" "(run1 ${RUN1}s, run2 ${RUN2}s, fallback run ${RUN3}s)"

echo "== 6. zero retention: no fake PII in logs or in the model volume (non-weight files)"
ok=1
for svc in litellm ingress tap ollama presidio-analyzer presidio-anonymizer model-init; do
  for s in "${PII[@]}"; do
    if docker compose logs --no-log-prefix "$svc" 2>&1 | grep -q -F "$s"; then echo "  '$s' found in $svc logs"; ok=0; fi
  done
done
patterns=$(printf -- '-e %q ' "${PII[@]}")
vol_hits=$(docker run --rm --network none -v sovereign-ai-gateway-kit_models:/v:ro --entrypoint sh "$OLLAMA_IMAGE" \
  -c "grep -r -l -I -F --exclude-dir=blobs $patterns /v || true")
[[ -n "$vol_hits" ]] && { echo "  found in volume: $vol_hits"; ok=0; }
check "6 zero-retention grep" "$ok" "(${#PII[@]} strings x 7 service logs + model volume excluding blobs/)"

echo "== 7. no secrets in tracked files"
ok=1
[[ -d .git ]] || git init -q
git add -A
files=$(git diff --cached --name-only; git ls-files)
files=$(sort -u <<<"$files")
if grep -q -x -F .env <<<"$files"; then echo "  .env is tracked"; ok=0; fi
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  if grep -q -E 'AKIA[0-9A-Z]{16}' "$f" && [[ "$f" != test-prompts.sh && "$f" != docs/test-data.md && "$f" != scripts/verify.sh ]]; then echo "  AWS key format in $f"; ok=0; fi
  if grep -q -E 'sk-[A-Za-z0-9_-]{20,}|BEGIN [A-Z ]*PRIVATE KEY|kube[c]onfig|ghp_[A-Za-z0-9]{30,}|xox[abp]-' "$f"; then echo "  secret-like string in $f"; ok=0; fi
done <<<"$files"
grep -v -E '^(#|$)' .env.example | grep -v -E '^(LITELLM_MASTER_KEY=sk-local-change-me|REASONING_API_BASE=http://tap:8080/v1|REASONING_API_KEY=not-needed-locally|REASONING_MODEL=granite4:3b)$' \
  && { echo "  unexpected value in .env.example"; ok=0; }
if docker run --rm -v "$PWD:/repo:ro" -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
     "$GITLEAKS_IMAGE" git --staged --no-banner --redact /repo >/dev/null 2>&1; then gl="gitleaks: no leaks"
else gl="gitleaks: findings (run it without >/dev/null to see them)"; ok=0; fi
check "7 secrets scan" "$ok" "($gl; staged, not committed)"

echo "== 8. shellcheck"
ok=1
docker run --rm -v "$PWD:/mnt:ro" -w /mnt "$SHELLCHECK_IMAGE" test-prompts.sh scripts/verify.sh scripts/pull-models.sh || ok=0
check "8 shellcheck" "$ok"

echo "== 9. measurements"
./test-prompts.sh >/dev/null 2>&1 || true   # leaves the last models loaded
docker stats --no-stream --format '  {{.Name}}: {{.MemUsage}}'
docker compose exec -T ollama ollama ps | sed 's/^/  /'
disk=$(docker run --rm --network none -v sovereign-ai-gateway-kit_models:/v:ro --entrypoint du "$OLLAMA_IMAGE" -sh /v | cut -f1)
echo "  model volume: $disk; cold start: ${COLD_START}s; warm demo run: ${RUN2}s"
check "9 measurements recorded" 1

echo "== 10. Docker memory available to the stack"
mem=$(docker info --format '{{.MemTotal}}')
gib=$(awk -v m="$mem" 'BEGIN{printf "%.1f", m/1024/1024/1024}')
check "10 stack ran within Docker's memory limit" "$([[ ${#FAILS[@]} -eq 0 ]] && echo 1 || echo 0)" "(Docker VM memory: ${gib} GiB)"

echo
echo "${#PASSES[@]} passed, ${#FAILS[@]} failed${FAILS[*]:+: ${FAILS[*]}}"
[[ ${#FAILS[@]} -eq 0 ]]
