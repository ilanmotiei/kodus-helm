# Kodus AI — Helm Chart

[![Release Helm chart](https://github.com/ilanmotiei/kodus-helm/actions/workflows/release.yml/badge.svg)](https://github.com/ilanmotiei/kodus-helm/actions/workflows/release.yml) [![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Self-hosted [Kodus AI](https://kodus.io) on any Kubernetes cluster (AKS, GKE, EKS, DigitalOcean, k3s, kind, …). One Helm release brings up the full stack:

- **api / worker / webhooks / web** — application
- **mcp-manager** *(optional)*, **ast** *(optional)* — code-review augmentations
- **postgres** (`pgvector`), **mongo:8**, **rabbitmq:4.2.2-management** — bundled, toggleable; point at external services if you prefer

## Install from the Helm registry

```bash
helm repo add kodus https://ilanmotiei.github.io/kodus-helm
helm repo update
helm install kodus kodus/kodus -n kodus --create-namespace -f my-values.yaml
```

…or pull and install from source (`git clone` then `helm install kodus charts/kodus -f my-values.yaml`).

See [CHANGELOG.md](CHANGELOG.md) for what changed between versions.

## Quick start

The minimal viable install needs four things from you: a public URL the browser will hit, an LLM API key, GitHub OAuth/App credentials, and database passwords.

```yaml
# my-values.yaml
global:
  publicUrl:
    web: https://kodus.example.com         # browser-facing URL (matches your Ingress host)

llm:
  provider: anthropic                      # see "Wiring an LLM" below
  model:    claude-sonnet-4-5-20250929
  apiKey:   sk-ant-...

github:
  oauth:
    enabled: true
    clientId:     Ov23li...
    clientSecret: ghs_...
  app:
    enabled: true
    slug:         kodus-myorg              # used to build the "Install App" button URL
    appId:        "1234567"
    clientId:     Iv23li...
    clientSecret: ghs_...
    privateKey: |
      -----BEGIN RSA PRIVATE KEY-----
      ...
      -----END RSA PRIVATE KEY-----

postgresql:
  auth: { password: pickAStrongPassword1 }
mongodb:
  auth: { password: pickAStrongPassword2 }
rabbitmq:
  auth: { password: pickAStrongPassword3 }

ingress:
  enabled:   true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    - { hosts: [kodus.example.com], secretName: kodus-tls }
  hosts:
    - host: kodus.example.com
      paths:
        - { path: /github/webhook,    pathType: Prefix, service: webhooks, port: 3332 }
        - { path: /gitlab/webhook,    pathType: Prefix, service: webhooks, port: 3332 }
        - { path: /bitbucket/webhook, pathType: Prefix, service: webhooks, port: 3332 }
        - { path: /azdevops/webhook,  pathType: Prefix, service: webhooks, port: 3332 }
        - { path: /forgejo/webhook,   pathType: Prefix, service: webhooks, port: 3332 }
        - { path: /,                  pathType: Prefix, service: web,      port: 3000 }
```

```bash
helm install kodus kodus/kodus -n kodus --create-namespace -f my-values.yaml
```

JWT/crypto secrets are auto-generated and remain stable across `helm upgrade` (the chart looks up the existing Secret to keep them).

## Wiring an LLM

Kodus is model-agnostic. Set exactly one provider:

```yaml
llm:
  provider: anthropic       # anthropic | openai | gemini | vertex | openrouter | groq | cerebras | novita | custom | auto
  model:    claude-sonnet-4-5-20250929
  apiKey:   sk-ant-...
  # baseUrl: ""              # only needed for `custom` (or to point a known
                             # provider at a private proxy / Azure-OpenAI)
  # vertexLocation: us-central1   # vertex only
```

The chart maps that to whatever combination of env vars Kodus actually expects. The most non-obvious case:

> **Anthropic key gotcha.** Kodus's source code reuses `API_OPEN_AI_API_KEY` as the Anthropic key when the model is `claude-*` ([byok-to-vercel.ts:401-405](https://github.com/kodustech/kodus-ai/blob/main/libs/code-review/infrastructure/agents/llm/byok-to-vercel.ts)). It is **not** named `API_ANTHROPIC_API_KEY` despite that variable also existing — that one isn't read on this code path. The chart hides this for you: `llm.apiKey` ends up in the right env var regardless of provider.

| Provider     | What `llm.apiKey` becomes inside the pod | Where you get the key |
|--------------|------------------------------------------|------------------------|
| `anthropic`  | `API_OPEN_AI_API_KEY` *(yes, really)* + `API_ANTHROPIC_API_KEY` | https://console.anthropic.com/settings/keys |
| `openai`     | `API_OPEN_AI_API_KEY`                    | https://platform.openai.com/api-keys |
| `gemini`     | `API_GOOGLE_AI_API_KEY` + `GEMINI_API_KEY` | https://aistudio.google.com/apikey |
| `vertex`     | `API_VERTEX_AI_API_KEY` (base64 SA JSON) | GCP IAM → service account → JSON key |
| `groq`       | `API_OPEN_AI_API_KEY` + base URL set to Groq | https://console.groq.com/keys |
| `cerebras`   | `API_OPEN_AI_API_KEY` + base URL set to Cerebras | https://cloud.cerebras.ai |
| `openrouter` | `API_OPEN_AI_API_KEY` + base URL set to OpenRouter | https://openrouter.ai/keys |
| `custom`     | `API_OPEN_AI_API_KEY` + your `llm.baseUrl` | self-hosted vLLM/Ollama/LiteLLM/etc. |

## GitHub setup

Two separate things on GitHub — sign-in (OAuth App) and code review (GitHub App).

### OAuth App — for sign-in

1. https://github.com/settings/applications/new
2. **Application name:** `Kodus self-hosted`
3. **Homepage URL:** `https://kodus.example.com`
4. **Authorization callback URL:** `https://kodus.example.com/api/auth/callback/github` (must match `global.publicUrl.web` exactly — protocol, host, no trailing slash)
5. Generate a client secret, paste both into `github.oauth.clientId/clientSecret`.

### GitHub App — for reviewing PRs

1. https://github.com/settings/apps/new
2. **Webhook URL:** `https://<webhooks-host>/github/webhook` (use `global.publicUrl.webhooks` if you set one, else `global.publicUrl.web`)
3. **Webhook secret:** generate; the chart auto-generates `CODE_MANAGEMENT_WEBHOOK_TOKEN` as well — set them to the **same** value, or set the chart's value to match yours via `secrets.CODE_MANAGEMENT_WEBHOOK_TOKEN: ...`
4. **Identifying and authorizing users → Callback URL:** `https://kodus.example.com/github-integration` *(same value as the App's "Setup URL" below)*
5. **Post installation → Setup URL (optional):** `https://kodus.example.com/github-integration` *(✱ critical — without it, GitHub never redirects users back to Kodus after install and the connection is never recorded)*. Check **Redirect on update**.
6. **Repository permissions:** Contents=Read, Issues=Read & write, Pull requests=**Read & write**, Checks=Read & write, Metadata=Read.
7. **Subscribe to events** *(also critical — empty list = no review will fire)*: Pull request, Push, Issue comment, Pull request review, Pull request review comment.
8. After creating, on the App's settings page copy: App ID, Client ID, Client Secret. Generate a private key (.pem). Paste the App's slug (URL fragment, e.g. `kodus-myorg`) and the values into `github.app.*`.

### Self-hosted GitLab / GitHub Enterprise / etc.

If you don't want a GitHub App, set `github.pat: <PAT>` and use the in-app UI to add a per-team integration (Settings → Integrations). The chart is identical otherwise; only the inbound webhook URL needs to be reachable from your Git server.

## Pointing at external infrastructure

Disable the bundled stateful services and provide connection details. Useful when you have an existing managed Postgres / Mongo / RabbitMQ.

```yaml
postgresql: { enabled: false }
mongodb:    { enabled: false }
rabbitmq:   { enabled: false }

config:
  API_PG_DB_HOST:     pg.example.com
  API_PG_DB_PORT:     "5432"
  API_PG_DB_USERNAME: kodus
  API_PG_DB_DATABASE: kodus_db
  API_MG_DB_HOST:     mongo.example.com
  API_MG_DB_PORT:     "27017"
  API_MG_DB_USERNAME: kodus
  API_MG_DB_DATABASE: kodus
  RABBITMQ_HOSTNAME:  rabbit.example.com

secrets:
  API_PG_DB_PASSWORD: ...
  API_MG_DB_PASSWORD: ...
  API_RABBITMQ_URI:   amqp://user:pass@rabbit.example.com:5672/kodus-ai
```

Note the bundled RabbitMQ image has the `rabbitmq_delayed_message_exchange` plugin auto-installed via init-container (Kodus declares an `x-delayed-message` exchange and crashes without it). If you point at external RabbitMQ, **install that plugin yourself** or Kodus will CrashLoop with `unknown exchange type 'x-delayed-message'`.

## Bring-your-own secrets (external-secrets / SealedSecrets / Vault)

```yaml
extraExistingSecrets:
  - kodus-llm-keys
  - kodus-git-creds
extraExistingConfigMaps:
  - kodus-extra-env
```

Each entry is a Secret/ConfigMap name in the same namespace. The chart loads them into every pod via `envFrom`, alongside the chart-managed Secret/ConfigMap.

## Ingress recipes

### Single host (recommended)

```yaml
global:
  publicUrl:
    web: https://kodus.example.com
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
  tls:
    - { hosts: [kodus.example.com], secretName: kodus-tls }
  hosts:
    - host: kodus.example.com
      paths:
        - { path: /github/webhook,    pathType: Prefix, service: webhooks, port: 3332 }
        - { path: /gitlab/webhook,    pathType: Prefix, service: webhooks, port: 3332 }
        - { path: /bitbucket/webhook, pathType: Prefix, service: webhooks, port: 3332 }
        - { path: /azdevops/webhook,  pathType: Prefix, service: webhooks, port: 3332 }
        - { path: /forgejo/webhook,   pathType: Prefix, service: webhooks, port: 3332 }
        - { path: /,                  pathType: Prefix, service: web,      port: 3000 }
```

### Split host (separate domain for the webhook receiver)

```yaml
global:
  publicUrl:
    web:      https://kodus.example.com
    webhooks: https://hooks.kodus.example.com
ingress:
  enabled: true
  className: nginx
  tls:
    - { hosts: [kodus.example.com, hooks.kodus.example.com], secretName: kodus-tls }
  hosts:
    - host: kodus.example.com
      paths:
        - { path: /, pathType: Prefix, service: web, port: 3000 }
    - host: hooks.kodus.example.com
      paths:
        - { path: /, pathType: Prefix, service: webhooks, port: 3332 }
```

## Reference: every value you can set

See [charts/kodus/values.yaml](charts/kodus/values.yaml) — heavily commented. Highlights:

| Block | What it controls |
|---|---|
| `global.publicUrl.web` / `.webhooks` | Browser-facing URLs; auto-derives `NEXTAUTH_URL`, `API_FRONTEND_URL`, `API_*_CODE_MANAGEMENT_WEBHOOK` for all 5 supported Git providers |
| `llm.*` | Provider, model, key, base URL — translated to whichever env vars Kodus actually reads |
| `github.oauth.*`, `github.app.*`, `github.pat` | Auth credentials; `github.app.slug` auto-fills the "Install App" button URL |
| `api`, `worker`, `webhooks`, `web`, `mcpManager`, `ast` | Per-component image, replicas, resources, probes, service type/annotations |
| `postgresql`, `mongodb`, `rabbitmq` | Bundled stateful services; `.enabled: false` to use external |
| `rabbitmq.delayedMessageExchange.enabled` | Auto-installs the `x-delayed-message` plugin (default `true`) |
| `ingress.*` | Standard k8s Ingress with multi-host + TLS |
| `extraConfig` / `extraSecrets` / `extraExistingSecrets` / `extraExistingConfigMaps` | Free-form additions / external secret refs |
| `autoGenerateSecrets` | Auto-generate JWT/crypto secrets and keep them stable across upgrades (default `true`) |

## Render / lint

```bash
helm lint charts/kodus
helm template kodus charts/kodus -f my-values.yaml --debug
```

## Layout

```
.
├── CHANGELOG.md
├── LICENSE
├── README.md
├── artifacthub-repo.yml          # Artifact Hub repo metadata
├── .github/workflows/release.yml # publishes to gh-pages on every push to main
└── charts/kodus/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── _helpers.tpl
        ├── _workload.tpl          # shared Deployment + Service renderer
        ├── NOTES.txt
        ├── configmap-env.yaml     # non-secret env vars (auto-derives from publicUrl + llm + github)
        ├── secret-env.yaml        # secret env vars (auto-derives crypto keys, llm.apiKey, github.*)
        ├── api.yaml, worker.yaml, webhooks.yaml, web.yaml, mcp-manager.yaml, ast.yaml
        ├── postgres.yaml          # StatefulSet + Service + pgvector init
        ├── mongodb.yaml           # StatefulSet + Service
        ├── rabbitmq.yaml          # StatefulSet + Service + delayed-msg plugin init-container
        ├── ingress.yaml
        └── serviceaccount.yaml
```

## Releasing

This repo uses [chart-releaser-action](https://github.com/helm/chart-releaser-action). To cut a new chart release:

1. Bump `version:` in [charts/kodus/Chart.yaml](charts/kodus/Chart.yaml) (semver — patch for chart-only fixes, minor for new values, major for breaking).
2. Add a section to [CHANGELOG.md](CHANGELOG.md).
3. Update the `artifacthub.io/changes` annotation block at the bottom of `Chart.yaml` so Artifact Hub shows the changelog on the package page.
4. Push to `main`. The release workflow packages the chart, creates a GitHub release with the `.tgz` attached, and updates `index.yaml` on the `gh-pages` branch.

## License

MIT for the chart — see [LICENSE](LICENSE). Kodus itself is dual-licensed; see [kodustech/kodus-ai](https://github.com/kodustech/kodus-ai/blob/main/license.md).
