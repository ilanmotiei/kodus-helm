# Known issues with self-hosted Kodus AI

This file documents upstream Kodus quirks and bugs we hit while building this chart. Most are not chart bugs — the chart compensates where it can. The list is here so users don't waste hours hitting the same walls.

If you find one of these annoying, the fix usually belongs in [`kodustech/kodus-ai`](https://github.com/kodustech/kodus-ai) or [`kodustech/kodus-installer`](https://github.com/kodustech/kodus-installer), not in this chart. Where the chart can work around it, we say so.

> **Scope.** Behaviors below were observed against `ghcr.io/kodustech/kodus-ai-*:latest` images as of 2026-05. Some may have been fixed upstream by the time you read this — `helm upgrade` to the latest chart version and re-test before assuming.

---

## 1. The Anthropic API key uses the OpenAI env var

When `API_LLM_PROVIDER_MODEL` matches `^claude[-_]`, Kodus's [`byok-to-vercel.ts`](https://github.com/kodustech/kodus-ai/blob/main/libs/code-review/infrastructure/agents/llm/byok-to-vercel.ts) constructs the Anthropic SDK with `apiKey: process.env.API_OPEN_AI_API_KEY`. The variable named `API_ANTHROPIC_API_KEY` in `.env.example` is **not** read on this path.

Setting only `API_ANTHROPIC_API_KEY` and selecting a Claude model produces a misleading 401:

```
AI_APICallError: invalid x-api-key
```

**Chart workaround:** the `llm.*` helper takes one `apiKey` and routes it to whichever env var Kodus actually reads for the chosen `provider`. For `provider: anthropic` the chart sets both `API_OPEN_AI_API_KEY` *and* `API_ANTHROPIC_API_KEY` to the same value so this stops mattering even after upstream fixes it. Users do not need to know about the variable overload.

## 2. Default review severity threshold is `critical`

After first install, the team's `code_review_config.suggestionControl.severityLevelFilter` is seeded as `"critical"`, which silently drops every suggestion below severity `critical` *before* it reaches the PR. The result is review summaries that say "No issues were found" while the agent log clearly shows it found bugs.

Confirm with:

```sql
SELECT "configValue"->'configs'->'suggestionControl'->>'severityLevelFilter'
FROM parameters WHERE "configKey" = 'code_review_config';
```

**Workaround.** Lower it via Web UI → Settings → Code Review → Suggestion Control → Severity, or directly:

```sql
UPDATE parameters
   SET "configValue" = jsonb_set("configValue",
                                 '{configs,suggestionControl,severityLevelFilter}',
                                 '"low"'::jsonb)
 WHERE "configKey" = 'code_review_config';
```

Worth doing on day one. The default is too aggressive for evaluating whether reviews are working at all.

## 3. GitHub App "Setup URL" is required for the install flow to record the installation

When a user clicks **Install** on the Kodus GitHub App, GitHub redirects them to the App's *Setup URL* (defined in **Identifying and authorizing users** + **Post installation** sections of the App settings). Without that URL, GitHub returns the user to github.com and Kodus never records the new installation, leaving them stuck in the onboarding loop with no way to move forward.

**Workaround.** When creating the GitHub App, set both:

- *Identifying and authorizing users → Callback URL* = `<publicUrl.web>/github-integration`
- *Post installation → Setup URL (optional)* = `<publicUrl.web>/github-integration` and tick **Redirect on update**

Then on every install GitHub will redirect to `…/github-integration?installation_id=N`, which Kodus's frontend resolves into a database record.

If a user is already stuck, the unblock is to navigate manually to `<publicUrl.web>/setup/github?installation_id=<id>`. The installation_id is fetchable via the GitHub App API (`GET /app/installations`).

## 4. GitHub App's "Subscribe to events" defaults to empty

A freshly-created GitHub App ships with `events: []`. GitHub will only send webhooks for events the App has explicitly subscribed to. If you configure everything else perfectly and open a PR, *nothing happens* — Kodus's webhook handler is never called.

Confirm via the GitHub API:

```bash
curl -H "Authorization: Bearer $JWT" https://api.github.com/app | jq .events
# []
```

**Workaround.** In the App settings → *Permissions & events* → *Subscribe to events*, tick: Pull request, Push, Issue comment, Pull request review, Pull request review comment. Re-install to re-fire the events you missed (existing installs only receive *new* events after the change).

## 5. Personal Access Token (PAT) integration deadlocks on org repos you don't admin

Kodus's PAT-based integration tries to install a per-repo webhook on every selected repo. The required GitHub API call is `GET/POST /repos/{owner}/{repo}/hooks`, which returns **404** when the token can read the repo but the user isn't an admin. Kodus then aborts the whole repo-registration flow with a 400 ("Bad Request: Not Found"), and the team's `integration_configs.repositories` row gets stuck pointing at the inaccessible repo. The onboarding screen keeps looping.

**Workaround.** Either deselect repos you don't admin before saving, or use the GitHub App integration path (the App's central webhook URL is set once at App creation, no per-repo calls needed). The PAT path is safe only when every selected repo is one you admin (typically: your own personal account, or repos in an org where you have admin rights and the PAT is SSO-authorized).

## 6. `web` rebuilds Next.js on first start; readiness probes time out

Tracked upstream in [kodus-ai#918](https://github.com/kodustech/kodus-ai/issues/918). On slow CPUs (CI runners, small dev nodes) the web Pod's first start takes long enough that the default readiness probe trips and Kubernetes restarts the pod, sometimes repeatedly. Subsequent restarts are fast because Next is cached on disk.

**Chart mitigation:** `web.readinessProbe.failureThreshold: 12` and a long `initialDelaySeconds`. Bump higher if you still see CrashLoops on first install only.

## 7. `api` and `webhooks` CrashLoopBackOff for ~60s on first install

Race condition. The `worker` pod is the one that creates the AMQP queues at startup. The `api` and `webhooks` pods try to bind subscribers to those queues, and if they reach RabbitMQ before the worker, they fail with `404 NOT_FOUND - no queue 'workflow.jobs.code_review.queue'`. Kubernetes' exponential backoff resolves it: by the second or third restart, the worker has created the queues and the binders succeed.

**Chart mitigation:** the `wait-for-deps` init container ensures app pods only start after Postgres / Mongo / RabbitMQ accept TCP, which closes the most common variant of this race. The remaining ~10s gap between worker startup and queue declaration is upstream and benign — pods stabilize on their own.

## 8. RabbitMQ needs the `rabbitmq_delayed_message_exchange` plugin

Kodus declares an exchange of type `x-delayed-message` for its workflow scheduling. Without the [community plugin](https://github.com/rabbitmq/rabbitmq-delayed-message-exchange) the broker rejects the declaration with `precondition_failed: unknown exchange type 'x-delayed-message'`, and every PR review crashes in Nest's Amqp connection bootstrap.

**Chart mitigation:** an init container downloads the official `.ez` release into a shared volume, the broker loads it via `RABBITMQ_PLUGINS_DIR`. Toggleable via `rabbitmq.delayedMessageExchange.enabled` (default `true`). If you point at external RabbitMQ (`rabbitmq.enabled: false`), install this plugin yourself.

## 9. OpenAI strict-JSON mode fails the dedup stage

When `llm.provider: openai` (or anything OpenAI-compatible-strict), the `AgentReviewStage.deduplicateSuggestions` call sends `response_format: { type: "json_object" }` but the user prompt does not contain the literal word "json". OpenAI returns:

```
'messages' must contain the word 'json' in some form, to use 'response_format' of type 'json_object'.
```

Anthropic and most OpenAI-compatible proxies ignore this constraint, so the bug is invisible to most users. The error is **non-fatal** — Kodus catches it and falls back to keeping all suggestions un-deduplicated. But it shows up as a noisy warning in the worker log on every review.

**Workaround.** None at the chart level. The fix belongs in upstream Kodus (either rephrase the prompt to include "json", or stop using strict JSON mode for that one call).

## 10. `@kody remember:` only works from inline review comments, not top-level PR comments

Kodus's chat handler ([`chatWithKodyFromGit.use-case.ts`](https://github.com/kodustech/kodus-ai/blob/main/libs/platform/application/use-cases/codeManagement/chatWithKodyFromGit.use-case.ts)) is structured around `@kody start-review` and `@kody -v business-logic` as hard-coded commands. Anything else routes through a generic conversation agent. To process the comment, the handler does:

```ts
const allComments = await codeManagementService.getPullRequestReviewComment(...);
const comment = allComments?.find(c => c.id === commentId);
if (!comment) return;     // <-- silent early-return
```

`getPullRequestReviewComment` calls `octokit.pulls.listReviewComments`, which returns **inline review comments only** — not top-level PR (issue) comments. So a `@kody remember: …` posted as a top-level PR comment fires the webhook, the handler runs for ~9 ms, finds no matching comment, and exits without ever reaching the conversation agent. No log, no reply, no error.

**Workaround.** Post `@kody remember: …` as an inline review comment on a specific line of the diff, not as a top-level PR comment. Or — better — wait for upstream to fix the comment-fetching path (the underlying API call should be `octokit.issues.listComments` for issue events).

## 11. `@kody remember:` requires the in-cluster MCP server + per-team activation

Memory creation/lookup is implemented as MCP tool calls (`createMemoryRule`, `KODUS_FIND_MEMORIES`) provided by Kodus's *internal* MCP server (the `kodusmcp` provider). The conversation agent only loads MCP tools if (1) `mcpManager.enabled` is true, (2) `API_MCP_SERVER_ENABLED=true` on the api pod, (3) the team has an `mcp_connections` row registered with status **`ACTIVE`** (uppercase — see issue 12) referencing an `mcp_integrations` row, and (4) the agent's HTTP call to `mcp-manager.svc:3101/mcp/connections` actually succeeds (see issue 13).

**Chart helper.** The `mcp.*` block in `values.yaml` flips `mcpManager.enabled` and wires every env var the api/worker/web pods need. Per-team provider activation (`kodusmcp` toggle, Composio key wiring, custom servers) still has to happen via the Kodus UI's Plugins page after install.

## 12. `mcp-manager` filters connections by `status='ACTIVE'` (uppercase)

If you provision MCP connections directly in Postgres (e.g. for automation), the `status` column is case-sensitive: `MCPManagerService.getConnections` queries with `params: { status = 'ACTIVE' }`. Lowercase `'connected'` or `'active'` rows are ignored.

```sql
UPDATE "mcp-manager".mcp_connections SET status = 'ACTIVE' WHERE provider = 'kodusmcp';
```

A `mcp_connections` row also requires an `integrationId` pointing at a row in `mcp_integrations`; that table holds the actual `baseUrl` and auth shape. Both rows are needed for the connection to be usable.

## 13. `mcp-manager` returns 500 from `GET /mcp/connections` with `EntityMetadataNotFoundError`

The upstream `ghcr.io/kodustech/kodus-mcp-manager:latest` image hits this on every request to its `/mcp/connections` endpoint:

```
EntityMetadataNotFoundError: No metadata for "MCPConnectionEntity" was found.
   at McpService.getConnections (/usr/src/app/dist/apps/mcp-manager/main.js:4887:64)
```

TypeORM in the mcp-manager service can't find its own entity metadata at runtime — likely a missing `entities: […]` in the data-source config of the compiled bundle. As a result, even with the connection rows correctly populated, the conversation agent's MCP tool fetch returns no servers and the agent stays tool-less. **Memories cannot be created from any GitHub comment until this is fixed upstream.**

**Workaround.** None at the chart level. Track [a public issue on this](https://github.com/kodustech/kodus-ai/issues) (file one if you don't see it).

## 14. Empty Git commits don't trigger reviews

Kodus's pipeline checks `lastAnalyzedCommit` and the diff size; a `git commit --allow-empty` is logged as `status:skipped, message:"No changed files in this pull request"` and does *not* invoke the LLM. If you're trying to re-trigger a review for testing, push a commit with at least one real file change, or use `@kody start-review` (which doesn't need new commits).

## 15. Helm `--reuse-values` carries forward `--set` values

Standard Helm behavior, but worth flagging: any value you've ever passed via `--set` on a previous `helm upgrade` is preserved across subsequent `--reuse-values` upgrades. Old API keys, old model names, etc. linger in the rendered Secret/ConfigMap until you explicitly override them. Use `--reset-values` (and re-supply your overlay file) when you want a clean slate.

## 16. `chart-releaser-action` requires a pre-existing `gh-pages` branch

If you fork this repo and re-enable the release workflow, the first run will fail with `fatal: invalid reference: origin/gh-pages` until you create the branch. Bootstrap with:

```bash
git switch --orphan gh-pages
echo "stub" > README.md
git add . && git commit -m "Bootstrap gh-pages"
git push -u origin gh-pages
git switch main
```

Subsequent runs work fine. (Documented here because we hit it.)

## 17. Server-side `WORKER_ROLE` is not set automatically in the worker image

`apps/worker/src/worker-role.ts:29` aborts boot with:

```
Error: WORKER_ROLE must be set to "code-review" or "analytics". Got undefined.
```

The upstream docker-compose sets it; the chart adds `WORKER_ROLE=code-review` and `COMPONENT_TYPE=worker` to `worker.extraEnv` by default so users don't see this. If you override `worker.extraEnv` you must include both.

---

## Filing upstream

The bugs above (especially 1, 2, 3, 4, 9, 10, 13) are worth fixing in [`kodustech/kodus-ai`](https://github.com/kodustech/kodus-ai/issues) so the chart can stop compensating for them. PRs welcome.
