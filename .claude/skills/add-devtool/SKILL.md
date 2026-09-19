---
name: add-devtool
description: Add a new self-hosted devtool (Jira, Bitbucket, Confluence, Artifactory, SonarQube, Woodpecker, etc.) to the devtools platform. Trigger whenever the user asks to "add a new devtool", "deploy <tool>", "onboard <tool> to the platform", or names a specific tool they want running on the devtools-labs cluster.
---

# Add a New Devtool

This skill wires a new tool into the three-repo GitOps platform that lives under
`devops-tashtiot/`:

| Repo | Role |
|---|---|
| `devtools-provision` | **What to deploy** — umbrella Helm chart per tool |
| `devtools-definition` | **How to configure per environment** — Helm values overrides |
| `devtools-labs` | **Infrastructure** — the minikube-on-EC2 host, ArgoCD bootstrap, shared RDS |

All three repos already live inside this one project directory (`devops-tashtiot/`) —
never create them elsewhere or as separate projects.

ArgoCD's `ApplicationSet` (`devtools-definition/applicationset.yaml`) auto-discovers
every directory under `devtools-provision/devtools/*` and deploys it with two Helm
sources merged in this order:

1. `devtools-provision/devtools/<tool>/values.yaml`
2. `devtools-definition/devtools/<tool>/values.yaml` (overrides on top)

Because the ApplicationSet references `$definition/devtools/{{path.basename}}/values.yaml`
unconditionally, **a tool directory must exist in both repos with the exact same name**,
or the sync will fail looking for the missing values file. Always create both sides
together. No changes to `applicationset.yaml` itself are needed for a new tool.

## 1. Pick the version — Data Center edition only, no cloud

Every devtool must be the **self-hosted / Data Center edition**, never the SaaS/cloud
variant (e.g. Bitbucket Data Center not Bitbucket Cloud, Confluence Data Center not
Confluence Cloud, Artifactory OSS/self-hosted not JFrog Cloud).

Pin the exact version to whatever is already validated in the sibling `tashtiot-apis`
repo's docker-compose files, e.g.:

```
../tashtiot-apis/docker-compose.artifactory.yaml
../tashtiot-apis/docker-compose.bitbucket.yaml
../tashtiot-apis/docker-compose.confluence.yaml
../tashtiot-apis/docker-compose.sonarqube.yaml
```

Read the relevant compose file, extract the image tag (e.g.
`releases-docker.jfrog.io/jfrog/artifactory-oss:7.77.5`), and use that exact version
for `appVersion` in `Chart.yaml` and for `image.tag` in values wherever the upstream
chart allows overriding it. If no docker-compose file exists yet for the tool, ask the
user which version to pin rather than guessing.

## 2. Create the provisions side (`devtools-provision/devtools/<tool>/`)

Structure to create, modeled on the **argocd** example — NOT the bitbucket example
(see warning below):

```
devtools-provision/devtools/<tool>/
├── Chart.yaml              # umbrella chart, depends on the subchart via file://
├── values.yaml             # values that are the SAME across every environment
├── charts/
│   └── <subchart>/         # the upstream chart, fully unpacked — NOT a .tgz
└── templates/              # optional: extra k8s resources (see step 4)
```

Fetch and unpack the upstream chart instead of vendoring a tarball:

```bash
helm repo add <alias> <upstream-repo-url>
helm pull <alias>/<chart> --version <pinned-version> --untar --untardir devtools-provision/devtools/<tool>/charts/
```

`--untar` extracts the chart directory directly — do not leave a `.tgz` in `charts/`.

**Important — bitbucket is a bad example to copy.** `devtools-provision/devtools/bitbucket/charts/`
currently contains only `bitbucket-1.20.1.tgz`, which predates this convention. Follow
`devtools-provision/devtools/argocd/charts/argo-cd/` instead, which is the fully
unpacked chart. Never commit a `.tar.gz` for a new devtool.

`Chart.yaml` (umbrella) example, mirroring `devtools-provision/devtools/argocd/Chart.yaml`:

```yaml
apiVersion: v2
name: <tool>
description: <Tool> Data Center <version>
type: application
version: 1.0.0
appVersion: "<pinned-version>"
dependencies:
  - name: <subchart>
    version: "<subchart-chart-version>"
    repository: "file://./charts/<subchart>"
```

`values.yaml` (umbrella, provisions side) holds only values that **won't change per
environment**: replica counts, resource requests/limits, chart-structural toggles,
volume definitions, non-secret config. Do not put ingress hostnames, DB connection
strings, credentials, or licenses here — those are environment-specific and belong in
`devtools-definition`.

## 3. Create the definition side (`devtools-definition/devtools/<tool>/values.yaml`)

Put everything that **differs per environment** here: ingress host
(`<tool>.devopstashtiot.page`), DB connection URL, admin credentials, license keys,
EKS-specific resource bumps, service type/annotations. Start the file with a comment
header like the existing examples:

```yaml
# EKS-specific overrides for <Tool> <version>.
# Merged on top of devtools-provision/devtools/<tool>/values.yaml by ArgoCD.
# Cloudflare tunnel: <tool>.devopstashtiot.page → nginx-ingress → <tool>-service
```

Passwords and DB credentials **may be committed in plaintext** in this repo — that's
the current convention here (see `devtools-definition/devtools/bitbucket/values.yaml`).
Do not introduce sealed-secrets/Vault/SOPS for these.

**License keys are the one exception — never commit a license in plaintext.** Store it
in AWS SSM Parameter Store as a `SecureString` and sync it into the cluster with an
`ExternalSecret`, following the pattern already built for bitbucket:

1. Put the license in SSM (Standard tier, free): `aws ssm put-parameter --name
   "/devtools/<tool>/license" --value "<license>" --type SecureString --region
   il-central-1 --overwrite`
2. In `devtools-provision/devtools/<tool>/values.yaml`, add both an empty plaintext
   placeholder and an SSM-path placeholder (see `bitbucketSecrets.license` /
   `bitbucketSecrets.licenseSsmParameter` in the bitbucket chart) — the plaintext key
   stays supported for any environment that hasn't adopted SSM yet, but new
   environments should only ever set the SSM path.
3. In the umbrella chart's `templates/secrets.yaml`, render a plain `Secret` when the
   plaintext value is set, or an `ExternalSecret` (`secretStoreRef: { name:
   aws-parameter-store, kind: ClusterSecretStore }`, `remoteRef.key: <the SSM path>`)
   when the SSM path is set instead — see `devtools-provision/devtools/bitbucket/templates/secrets.yaml`.
4. In `devtools-definition/devtools/<tool>/values.yaml`, set only the SSM path — never
   the plaintext license field.

This requires the `external-secrets-operator` devtool (already deployed under
`clusters-provision/clusters/external-secrets-operator/`) and its cluster-wide
`ClusterSecretStore` named `aws-parameter-store`, which reads AWS credentials from the
minikube EC2 instance's IAM role via IMDS — no static AWS keys anywhere. If the new
tool's SSM path falls outside `/devtools/*`, extend the `ssm_parameter_store_read` IAM
policy resource ARN in `devtools-labs/terraform/modules/minikube/iam.tf` accordingly.

**Admin password — reuse the one shared secret, `/devtools/admin/password`.** Every
devtool on this platform shares the same admin password (already in SSM as a
`SecureString`, populated once — never create a per-tool `/devtools/<tool>/admin/...`
parameter). Wire it in following the bitbucket pattern
(`bitbucketSecrets.admin` / `bitbucketSecrets.adminPasswordSsmParameter` in
`devtools-provision/devtools/bitbucket/values.yaml` and the second half of
`devtools-provision/devtools/bitbucket/templates/secrets.yaml`):

1. In `devtools-provision/devtools/<tool>/values.yaml`, add an `<tool>Secrets.admin`
   block (`username`, `displayName`, `emailAddress` — plaintext, non-secret) plus an
   `<tool>Secrets.adminPasswordSsmParameter` placeholder (empty string).
2. In the umbrella chart's `templates/secrets.yaml`, render a plain `Secret` (e.g.
   `<tool>-sysadmin`) with `username`/`displayName`/`emailAddress` from the values
   above, then — guarded by `if .Values.<tool>Secrets.adminPasswordSsmParameter` — a
   second `ExternalSecret` with `target.creationPolicy: Merge` (not `Owner`) that
   patches only the `password` key from
   `remoteRef.key: {{ .Values.<tool>Secrets.adminPasswordSsmParameter }}` into that same
   Secret. `Merge` is required here — it lets the plain Secret and the ExternalSecret
   both write into one object without one owning/deleting the other.
3. In `devtools-definition/devtools/<tool>/values.yaml`, set
   `<tool>Secrets.adminPasswordSsmParameter: "/devtools/admin/password"` and the
   plaintext `admin.username`/`displayName`/`emailAddress` fields.

**Check whether the chart actually consumes these secrets before wiring them —
don't assume it does.** Bitbucket's chart happens to support full GitOps bootstrap:
it exposes `SETUP_LICENSE` and `sysadminCredentials` in
`devtools-provision/devtools/bitbucket/charts/bitbucket/templates/statefulset.yaml`,
wired from `bitbucket.license`/`bitbucket.sysadminCredentials` in values, which
consume the `<tool>-license`/`<tool>-sysadmin` Secret names and keys from step 2
above at container startup — no manual browser step needed. **This is not universal.**
Confluence's chart supports the license (`ATL_LICENSE_KEY`) but not sysadmin
auto-creation. Jira's chart (confirmed by pulling the chart and checking
Atlassian's own docs) supports **neither** — no license or sysadmin env var exists
at all.

**This matches Atlassian's own documented limitation, not a quirk of these
particular charts:** pre-provisioning a license via a Kubernetes Secret in
`values.yaml` is only supported for Confluence, Bitbucket, and Bamboo. Jira and
Crowd deployments can *only* get a license through the post-deployment setup
wizard — there's no Secret/env-var path for them at all, so don't spend time
looking for one. Of the three license-eligible products, Atlassian's docs call
out Bitbucket and Bamboo specifically as going further: their charts can be
**fully configured at deploy time** (license + `sysadminCredentials` together),
so no manual setup wizard is needed post-install. Confluence only gets the
license half of that — the admin user still has to be created through the
one-time browser wizard. If Bamboo or Crowd are ever onboarded to this
platform, expect Bamboo to follow the Bitbucket pattern (full GitOps bootstrap)
and Crowd to follow the Jira pattern (setup wizard only, license included).

Before adding a `<tool>-license`/`<tool>-sysadmin` Secret + ExternalSecret to the
umbrella chart's `templates/secrets.yaml`, `grep` the pulled upstream chart's
`templates/statefulset.yaml` (and values.yaml) for `LICENSE`/`SETUP_`/`sysadmin`
env vars to confirm it's actually consumed. **If the chart doesn't consume it, do
not create the Secret/ExternalSecret at all** — an unused Secret that looks like
automation but isn't is worse than no Secret, since it's misleading dead weight.
In that case: still put the license in SSM (step above) and rely on the shared
`/devtools/admin/password` SSM parameter, but read both directly with
`aws ssm get-parameter --with-decryption` when doing the one-time manual setup
wizard, and say so explicitly in a comment at the top of that tool's
`devtools-definition/devtools/<tool>/values.yaml` so the limitation isn't
rediscovered by surprise later.

## 4. Optional: extra templates on the umbrella chart

If the upstream subchart needs resources the umbrella chart should own (e.g. Secrets
that the subchart references by name, extra PVCs), add a `templates/` folder directly
under `devtools-provision/devtools/<tool>/` (sibling to `charts/`) — Helm treats the
umbrella chart's own `templates/` as first-class. Follow the pattern in
`devtools-provision/devtools/bitbucket/templates/secrets.yaml` and
`shared-home-pvc.yaml`: define a top-level values key (e.g. `<tool>Secrets`) in the
umbrella `values.yaml` as empty placeholders, populate the real values in
`devtools-definition`, and render them into `Secret`/`PVC` objects that the subchart
consumes via `secretName` references. "argocd" in this pattern's origin is just the
example tool name — apply the same approach for any tool.

## 5. Database — reuse the existing RDS instance, via a self-provisioning init container

Never provision a new `aws_db_instance` for a devtool, and never create the database
by hand over `psql`. Every devtool that needs Postgres provisions its own
database declaratively, as part of its own Helm chart — no separate
Terraform layer, no manual step.

There is one shared Postgres instance (`devtools-rds`) managed by Terragrunt at
`devtools-labs/terraform/live/devtools/rds/`. `aws_db_instance` only creates one
initial database (`bitbucket`, via `db_name`) — every other tool's database is
created lazily, the first time its pod starts, by an `additionalInitContainer`
declared in `devtools-definition/devtools/<tool>/values.yaml` (`confluence`,
`bitbucket`, and `jira` all do this — copy their pattern). The init container:

1. Runs a small `postgres:17-alpine` image with an idempotent `psql` script
   (`CREATE DATABASE ... OWNER ...`, guarded by `SELECT ... WHERE`, safe to
   re-run on every pod restart).
2. Authenticates as the RDS **master** user, sourced from a `rds-admin-credentials`
   Secret — populated via an `ExternalSecret` (see
   `devtools-provision/devtools/<tool>/templates/rds-admin-secret.yaml`,
   guarded by `rdsAdmin.usernameSsmParameter`/`passwordSsmParameter` values) from
   two SSM SecureString parameters: `/devtools/rds/admin-username` and
   `/devtools/rds/admin-password`. Requires the `external-secrets-operator`
   devtool to already be deployed (it is, automatically, via the same
   ApplicationSet).
3. **The app itself also connects as that same RDS master user** — do not create a
   dedicated per-tool login (e.g. a shared `devtools-apps` role) with its own
   password. The tool's own `<tool>-db` Secret's `username`/`password` keys are
   populated from the *same* `rdsAdmin.usernameSsmParameter`/`passwordSsmParameter`
   SSM params, via an `ExternalSecret` with `creationPolicy: Merge` (see
   `bitbucket`/`confluence`/`jira`/`sonarqube`'s `templates/secrets.yaml` — a
   plain `Secret` holds the non-secret `url` key, merged with an `ExternalSecret`
   for `username`/`password`). The master user just creates/owns the database;
   nothing else needs its own role.
   **Do not deviate from this** — if a tool's init container manages its own
   dedicated role name with a hardcoded password (as `artifactory` and `xray`
   both used to, sharing the role name `devtools-apps` with different
   passwords), every pod restart of either tool silently overwrites the
   other's password, causing recurring "password authentication failed"
   crash loops. This exact bug took down Artifactory on 2026-07-07 — see
   `devtools-provision@c088577` / `devtools-definition@d56e1da` for the fix.

To onboard a new tool's database:

1. In `devtools-provision/devtools/<tool>/`, add a
   `templates/rds-admin-secret.yaml` (copy from `bitbucket` or `confluence`
   verbatim) and an `rdsAdmin: {usernameSsmParameter: "", passwordSsmParameter: ""}`
   placeholder block in `values.yaml`. In `templates/secrets.yaml`, add the
   `<tool>-db` Secret (plain `stringData` for `url` only) plus an
   `ExternalSecret` with `creationPolicy: Merge` sourcing `username`/`password`
   from `.Values.rdsAdmin.usernameSsmParameter`/`passwordSsmParameter` (copy
   `bitbucket`'s `templates/secrets.yaml` verbatim, renaming the Secret).
2. In `devtools-definition/devtools/<tool>/values.yaml`, set
   `rdsAdmin.usernameSsmParameter`/`passwordSsmParameter` to
   `/devtools/rds/admin-username`/`/devtools/rds/admin-password` (already
   populated in SSM — don't recreate them), and add an `additionalInitContainer`
   under the subchart's own values key (e.g. `confluence.additionalInitContainers`)
   following the confluence/bitbucket example — same script, just change
   `APP_DB_NAME`. No `APP_DB_USER`/`APP_DB_PASSWORD` env vars, no `CREATE ROLE`/
   `ALTER ROLE`/`GRANT` — only `CREATE DATABASE ... OWNER "$ADMIN_USER"`.
3. Wire the resulting connection URL into the same file
   (`jdbc:postgresql://<rds-address>:5432/<tool>`, using the `rds` module's
   `address`/`port` outputs).

Do not run `CREATE DATABASE`/`CREATE USER` manually anywhere — if a tool needs
something the shared script doesn't yet support, extend that tool's own
`additionalInitContainers` command in its `devtools-definition` values file.

**If the instance is too small** (storage or `db.t3.micro` CPU/connections becomes a
bottleneck once the new tool's data lands on it), bump `allocated_storage` /
`max_allocated_storage` / `instance_class` via the **inputs** in
`devtools-labs/terraform/live/devtools/rds/terragrunt.hcl` (these are now Terraform
variables on the `rds` module, not hardcoded) and run `terragrunt apply` in that
directory. Confirm with the user before applying — resizing an RDS instance can
require a brief reboot/downtime, and moving off `db.t3.micro` or past the 20GB
free-tier storage threshold takes the instance out of the AWS Free Tier (call out the
estimated cost per the root `CLAUDE.md` cost-awareness rules before provisioning).

## 6. Expose it

Set the subchart's own ingress (most Data Center charts ship one, e.g. bitbucket's
`ingress.create`) to host `<tool>.devopstashtiot.page`, `https: false`, and
`nginx.ingress.kubernetes.io/ssl-redirect: "false"` — TLS terminates at Cloudflare,
not in-cluster.

**Ignore the root `CLAUDE.md`'s instructions to edit `cloudflared`'s `config.yml` on
"the server" — that doesn't apply to this platform.** Here, `cloudflared` itself runs
as an in-cluster devtool (`clusters-provision/clusters/cloudflared/`) with a single
catch-all ingress rule (`service:
http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80` — see its
`values.yaml`); routing to the right tool happens via nginx-ingress matching the
`Host` header on each tool's own Ingress resource, which you just created above. So
the *only* remaining step is the DNS record — add a CNAME for the new subdomain
pointing at the tunnel (`7de872ce-2826-42fb-9aea-325e10e3e5fc.cfargotunnel.com`).
**Confirm with the user before making the live Cloudflare API call** — it touches
shared infrastructure outside this repo.

## 7. Always check whether the DNS record actually exists

Never assume the CNAME from step 6 is in place, whether or not you were the one who
added it. Before finishing, check it directly against Cloudflare's authoritative
nameservers, not a local/cached resolver (regular DNS caches — including a plain
`dig <tool>.devopstashtiot.page` without specifying a nameserver — can return a stale
empty answer even after the record exists):

```bash
dig +short @coraline.ns.cloudflare.com <tool>.devopstashtiot.page A
```

- Resolves to a Cloudflare proxy IP (`104.x.x.x` / `172.67.x.x`) → the record exists.
- Empty response → the record does not exist yet.

**Always tell the user the result either way** — don't silently assume success or
silently skip the check. If it's missing, say so explicitly and offer to create it (per
step 6) or ask the user to confirm they'll add it themselves.

## Checklist

- [ ] Version pinned from the matching `../tashtiot-apis/docker-compose.<tool>.yaml`, Data Center edition
- [ ] `devtools-provision/devtools/<tool>/` created: `Chart.yaml`, `values.yaml`, unpacked chart under `charts/<subchart>/` (no `.tgz`)
- [ ] `devtools-definition/devtools/<tool>/values.yaml` created with the same tool name, env-specific values only
- [ ] If the tool has a license key, it's in SSM Parameter Store + synced via ExternalSecret — never plaintext in git
- [ ] Confirmed (by grepping the pulled chart, not assuming) whether it actually consumes a license/sysadmin Secret at container startup
- [ ] If it does: admin password wired from the shared `/devtools/admin/password` SSM parameter via an ExternalSecret with `creationPolicy: Merge` (not a new per-tool password), and both license + admin user are applied automatically at startup (GitOps) — no manual setup-wizard step
- [ ] If it doesn't: no `<tool>-license`/`<tool>-sysadmin` Secret created (avoid inert plumbing) — noted in a comment in `devtools-definition/devtools/<tool>/values.yaml` that the one-time browser setup wizard is required, reading the license/admin password directly from SSM
- [ ] Optional `templates/` added for extra Secrets/PVCs if the subchart needs them
- [ ] DB provisioned via an `additionalInitContainer` + `rds-admin-credentials` ExternalSecret in the tool's own chart/values (see section 5), not a manual `psql` session or a new RDS instance
- [ ] Ingress host set to `<tool>.devopstashtiot.page`, TLS disabled in-cluster
- [ ] Cloudflare DNS + `cloudflared` ingress rule added (with user confirmation)
- [ ] DNS existence verified against Cloudflare's authoritative nameservers (not assumed) and the result reported to the user either way
- [ ] Confirmed both repo directories use the identical tool name so ArgoCD's ApplicationSet merges correctly
