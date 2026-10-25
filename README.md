# tmpl-webapp-bicep

Template for a team app on Azure Container Apps. A vended repo deploys as-is: the
placeholder in `app/` reaches dev on the first push to `main`. In this template
repo itself the deploy and what-if workflows are skipped (no `APP_NAME`).

## What `infra/main.bicep` creates

Inside `rg-<app>-<env>`:

| Resource | Default | Switch |
|---|---|---|
| Container App `ca-<app>-<env>` | on | |
| Key Vault `kv-<app>-<env>` (RBAC) | on | |
| Storage account + queue `jobs` (identity only) | off | `enableStorage` |
| Worker Container App, same image, no ingress | off | `enableWorker` |
| Postgres Flexible Server, Entra-only | off | `enablePostgres` |

It references, never creates: the department's Container Apps environment and
registry (platform-shared) and the runtime identity (vending).

The app runs as `id-<app>-<env>-runtime`. It reads secrets from Key Vault and
storage by identity; there are no passwords in the app or the pipeline. Its roles
were granted by vending; this repo cannot grant roles. If the app needs another
one (for example on an AI service), ask for it through its `projects/<app>.yaml`.

## Who owns what

`infra/main.bicep` owns every property of the app: sizing, scale, env vars. The
only thing passed in at deploy time is the image tag. Do not set those properties
anywhere else (portal, `az containerapp update`), or the next deploy puts them back.

## Pipelines

| Workflow | When | Runs as |
|---|---|---|
| `ci.yml` | every PR and push | no Azure access |
| `infra-plan.yml` | PRs touching `infra/` | plan identity (What-If Reader) |
| `deploy-dev.yml` | push to `main` | dev deploy identity: build `<app>:<sha>` on the runner, push, deploy to dev |
| `release.yml` | tag `vX.Y.Z` (a published release) | dev identity names the tested image `<app>:vX.Y.Z`; prod identity deploys it after approval |

### Releasing to prod

Every merge reaches dev. Prod only gets versions:

1. **Releases** → **Draft a new release** → tag `v1.2.3` on `main` → **Publish release**
   (or `git tag v1.2.3 && git push origin v1.2.3`).
2. `release.yml` checks the tag is `vX.Y.Z` on a commit of `main` that was deployed
   to dev, and adds the version to that same image in the registry (no rebuild).
   A version never moves: reusing a tag for another image fails.
3. Approve the `prod` deployment. Prod runs `<registry>/<app>:v1.2.3`.

Release tags are protected: only the owning team can create them, and nobody can
move or delete them.

Rollback: dev, run **deploy-dev** by hand with `image-tag` set to an earlier commit
SHA; prod, run **release** on an earlier tag (`gh workflow run release.yml --ref v1.2.2`).

Actions are pinned by commit SHA; Dependabot keeps them up to date.

Every Azure login goes through `.github/actions/azure-login`: a full OIDC login,
repeated with a fresh token and a growing delay (up to 10 minutes) until the
identity can use the subscription.
New role assignments take minutes to take effect, e.g. on the first deploy right
after vending; without the wait that deploy would fail with "No subscriptions found".

## Variables

All set by vending; nothing to edit after the repo is created. `infra/*.bicepparam`
read them with `readEnvironmentVariable`.

## Make it yours

1. Replace `app/` with the real app (keep port 8080 or change `targetPort`).
2. Turn on what you need in `infra/main.<env>.bicepparam`.
3. Add the app's tests to `ci.yml` and its ecosystem to `dependabot.yml`.
4. Replace the teams in `.github/CODEOWNERS`.
