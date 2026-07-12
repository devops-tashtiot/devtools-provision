# devtools-provision

Umbrella Helm charts for the self-hosted devtools platform — Jira, Bitbucket, Confluence,
Artifactory, ArgoCD, and Xray, all self-hosted Data Center editions running on the
`devtools-labs` cluster. This is the "what to deploy" half of a provision/definition pair;
environment-specific values (ingress hosts, credentials, EKS resource sizing) live in the
sibling [`devtools-definition`](https://github.com/devops-tashtiot/devtools-definition)
repo, and both are auto-discovered by an ArgoCD `ApplicationSet`. The cluster-infra
equivalent of this pair is
[`clusters-provision`](https://github.com/devops-tashtiot/clusters-provision)/
[`clusters-definition`](https://github.com/devops-tashtiot/clusters-definition).

## What's here

Each directory under `devtools/` is an umbrella Helm chart that vendors a fully unpacked
upstream chart under `charts/<subchart>/` (never a `.tgz`) via a `file://` dependency in
`Chart.yaml`.

| Tool | Upstream chart vendored |
|---|---|
| `argocd` | `argo-cd` |
| `artifactory` | `artifactory` |
| `bitbucket` | `bitbucket` |
| `confluence` | `confluence` |
| `jira` | `jira` |
| `xray` | `xray` |

## Conventions

- Self-hosted / Data Center edition, version pinned to whatever's already validated in
  `../tashtiot-apis/docker-compose.<tool>.yaml`.
- Shared Postgres instance (`devtools-rds`) — each tool provisions its own database/role
  lazily via an init container, no separate RDS instance per tool.
- One shared admin password (`/devtools/admin/password` in SSM) across every tool.
- License keys, where applicable, go through SSM + `ExternalSecret` — never plaintext.

## Adding a new tool

See the `add-devtool` skill (`.claude/skills/add-devtool/SKILL.md` at the project root) for
the full onboarding checklist.

See [`CLAUDE.md`](./CLAUDE.md) for the fuller architecture writeup.
