# CLAUDE.md — devtools-provision

This repo holds the umbrella Helm charts for the self-hosted devtools platform (Jira,
Bitbucket, Confluence, Artifactory, ArgoCD, Xray, ...). It's the "what to deploy" half of
the `devtools-provision`/`devtools-definition` pair — the devtool-layer counterpart to
`clusters-provision`/`clusters-definition` (cluster-wide infra like ingress/secrets/
tunnel/OIDC — see that pair's `CLAUDE.md` and the `add-cluster-provision` skill instead for
infra-level tools).

## Role in the Architecture

ArgoCD's `ApplicationSet` (in `devtools-definition/applicationset.yaml`) auto-discovers every
directory under `devtools/*` here and deploys it from two merged Helm value sources:
`devtools/<tool>/values.yaml` (this repo, env-invariant defaults) applied first, then
`devtools-definition/devtools/<tool>/values.yaml` overriding on top. A tool directory must
exist in both repos under the identical name, or the `ApplicationSet`'s unconditional
`$definition` reference fails.

## Repository Structure

```
.
└── devtools/
    └── <tool>/
        ├── Chart.yaml       # umbrella chart, dependencies: block
        ├── values.yaml      # env-invariant defaults
        ├── charts/
        │   └── <subchart>/  # upstream chart, fully unpacked — never a .tgz
        └── templates/       # optional: extra Secrets/PVCs the subchart needs
```

Every devtool here uses the same pattern — an umbrella chart vendoring an unpacked upstream
chart. Unlike `clusters-provision`, there's no "plain, self-authored" fallback pattern in
this repo, because every devtool onboarded so far has had a real upstream chart to vendor
(if one ever doesn't, treat that as worth flagging explicitly rather than silently
freehanding templates).

## Conventions specific to devtools (see the `add-devtool` skill for the full checklist)

- **Data Center / self-hosted edition only** — never the SaaS/cloud variant. Version asked from the user.
- **Database** — every tool needing Postgres reuses the one shared `devtools-rds` instance;
  its own database is created lazily by an init container wired in `devtools-definition`
  (`additionalInitContainer`/`customInitContainersBegin`), never a new RDS instance or a
  manual `psql` session. **Connect as the shared RDS admin user, not a dedicated per-tool
  role** — the `<tool>-db` Secret's `username`/`password` come from an `ExternalSecret`
  pointed at `rdsAdmin.usernameSsmParameter`/`passwordSsmParameter` (see
  `bitbucket`/`confluence`/`jira`/`sonarqube`'s `templates/secrets.yaml`), and the init
  container only needs `CREATE DATABASE ... OWNER <admin>` if missing — no `CREATE ROLE`.
  Don't invent a dedicated shared role with its own hardcoded password: two tools' init
  containers managing the same role name with different passwords means every pod restart of
  either silently overwrites the other's password, causing recurring "password authentication
  failed" crash loops that look unrelated to whatever just changed — this exact bug took down
  Artifactory on 2026-07-07 (fixed in `devtools-provision@c088577`/`devtools-definition@d56e1da`).
- **Admin password** — every devtool shares one SSM parameter,
  `/devops/terraform-created/admin/password`, wired via an `ExternalSecret` with `creationPolicy: Merge`.
  Never create a per-tool admin password parameter.
- **License keys** — SSM `SecureString` + `ExternalSecret`, never plaintext in git.
  Confirm the chart actually consumes a license/sysadmin Secret at container startup before
  wiring one — some charts (Jira) have no such mechanism at all and need the one-time
  browser setup wizard instead.
- **Ingress** — host `<tool>.devopstashtiot.page`, `https: false`, TLS terminates at
  Cloudflare, not in-cluster.

## Currently tracked tools

`argocd`, `artifactory`, `bitbucket`, `confluence`, `jira`, `xray` — each an umbrella chart
under `devtools/<tool>/`.

## Adding a New Tool

Use the `add-devtool` skill — don't freehand the chart structure, secrets pattern, or
database provisioning. Only use this repo for end-user applications; cluster-wide
infrastructure (ingress, secrets operator, tunnel, identity provider) belongs in
`clusters-provision`/`clusters-definition` instead (`add-cluster-provision` skill).
