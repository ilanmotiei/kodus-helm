# Changelog

All notable changes to the **kodus** Helm chart are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the chart adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The chart's `version` is independent of the Kodus `appVersion`; bumping the chart for chart-only changes does not require an upstream Kodus release.

## [Unreleased]

## [0.1.0] - 2026-05-07

First public release. Cloud-generic Helm chart for self-hosting Kodus AI on any Kubernetes cluster (AKS, GKE, EKS, DigitalOcean, k3s, kind, …).

### Added

- **6 app services** as separate Deployments — `api`, `worker`, `webhooks`, `web`, optional `mcp-manager`, optional `ast`. Each gets its own image, replicas, resources, probes, service type, and annotations block.
- **Bundled stateful services**, all toggleable: `postgresql` (`pgvector/pgvector:pg16`), `mongodb` (`mongo:8`), `rabbitmq` (`rabbitmq:4.2.2-management`). Each runs as a single-replica StatefulSet with a PVC; flip `.enabled: false` to point at external infrastructure.
- **`rabbitmq.delayedMessageExchange.enabled`** (default `true`) — an init container downloads the official `rabbitmq_delayed_message_exchange-4.2.0.ez` plugin into a shared volume so the broker accepts Kodus's `x-delayed-message` exchange. Without this, every PR review crashes with `precondition_failed: unknown exchange type`.
- **`wait-for-deps` init containers** on every app pod that nc-poll Postgres / MongoDB / RabbitMQ before the main container boots. Removes the boot-order race that otherwise puts api/worker/webhooks into `CrashLoopBackOff` for the first ~60 seconds after install.
- **`llm.*` block** — single place for LLM provider, model, key, and base URL. Supports `anthropic`, `openai`, `gemini`, `vertex`, `openrouter`, `groq`, `cerebras`, `novita`, `custom`, `auto`. The chart maps `llm.apiKey` to whichever env var Kodus actually reads (notably hiding the fact that Kodus uses `API_OPEN_AI_API_KEY` for the Anthropic key).
- **`github.{oauth,app,pat}` blocks** — single place for GitHub OAuth App, GitHub App, and PAT credentials. `github.app.slug` auto-derives `WEB_GITHUB_INSTALL_URL`.
- **`global.publicUrl.{web,webhooks}`** — set the browser-facing URL once and the chart auto-fills `NEXTAUTH_URL`, `API_FRONTEND_URL`, `API_USER_INVITE_BASE_URL`, plus the per-provider webhook URLs (`API_GITHUB_CODE_MANAGEMENT_WEBHOOK`, `API_GITLAB_*`, `GLOBAL_BITBUCKET_*`, `GLOBAL_AZURE_REPOS_*`, `API_FORGEJO_*`).
- **`autoGenerateSecrets`** (default `true`) — if user doesn't supply `API_JWT_SECRET`, `API_CRYPTO_KEY`, `WEB_NEXTAUTH_SECRET`, etc., the chart generates them via `randAlphaNum`. Uses Helm's `lookup` to read the existing Secret on `helm upgrade` so values stay stable across runs (issued JWTs remain valid).
- **`extraConfig`, `extraSecrets`, `extraExistingSecrets`, `extraExistingConfigMaps`** — escape hatches for free-form additions and external Secret/ConfigMap references (works with external-secrets, SealedSecrets, Vault, etc.).
- **`ingress.*`** — standard k8s Ingress with multi-host + TLS, designed for `cert-manager` annotations. Single-host and split-host (separate domain for the webhook receiver) recipes are in the README.
- **`Service` annotations + `loadBalancerClass`** — per-component, so users on managed clouds can wire up Tailscale Operator, AWS NLB, GCP internal LB, etc.
- **NOTES.txt** — installation summary including `port-forward` snippets for namespace-only access.

### Notes

- The chart is published at `https://ilanmotiei.github.io/kodus-helm` once GitHub Pages is enabled (see [README §Install from the Helm registry](README.md)).
- `appVersion` is set to `latest` and components default to the `:latest` image tag. Pin via `global.imageTag` (or per-component `image.tag`) for reproducibility.

[Unreleased]: https://github.com/ilanmotiei/kodus-helm/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ilanmotiei/kodus-helm/releases/tag/v0.1.0
