# CLAUDE.md — devtools-provision/devtools/artifactory

This tool is currently the one exception to the repo-wide "Data Center only" convention (see
the parent `CLAUDE.md`): it runs the **OSS edition**, switched on 2026-07-11 because this
platform has no JFrog license. This file covers reverting that back to Pro.

## Reverting from OSS back to Pro

Needs changes in **both** `devtools-provision` and `devtools-definition`; there's no
automated toggle, so work through this checklist in order.

**1. This directory's `values.yaml`** — remove (don't just comment out) the OSS-only
overrides added in commits `a7224af`, `dd88618`, `5457b8d`:
- The `image: repository: jfrog/artifactory-oss` block. Deleting it reverts to the upstream
  chart's own default, `jfrog/artifactory-pro` (tag still resolves to `Chart.AppVersion`).
- The `jfconnect: enabled: false` / `onemodel: enabled: false` / `evidence: enabled: false`
  block and its explanatory comment. These three exist purely to work around an upstream
  chart bug where `router.requiredServiceTypes` doesn't match the OSS-image regex guards in
  `charts/artifactory/templates/artifactory-statefulset.yaml` (see that comment for the full
  mechanism) — on Pro none of that applies, the chart's own defaults (`enabled: true`) are
  correct again.
- The `license: {}` comment block under the inner `artifactory.artifactory` key currently
  says the OSS image "doesn't accept a license at all — this stays empty permanently." Once
  reverted to Pro, delete that comment; license wiring moves to `devtools-definition`
  (step 3 below), same as before the OSS switch.

**2. `Chart.yaml`, and the parent repo's `CLAUDE.md`/`README.md`** — revert the cosmetic
"Artifactory OSS" wording back to "Artifactory Data Center" in `Chart.yaml`'s `description`,
and remove the Artifactory-is-the-one-exception carve-outs from the parent `CLAUDE.md`'s Data
Center bullet (including the pointer to this file) and from `README.md`'s intro paragraph and
Conventions section.

**3. `devtools-definition/devtools/artifactory/values.yaml`** — this is where the actual
license and storage get wired back in:
- Get a real license and put it in SSM:
  ```bash
  aws ssm put-parameter --name "/devtools/artifactory/license" \
    --value "<license text>" --type SecureString --region il-central-1
  ```
- Set `wrapper.artifactorySecrets.licenseSsmParameter` to that path.
- Set `artifactory.artifactory.license.secret: artifactory-license` and
  `.dataKey: artifactory.lic` (mirrors the `admin` block already wired in this repo's
  `values.yaml`).
- Re-add the S3 persistence override removed in `devtools-definition@cf3758f` — the bucket
  and instance IAM policy were never torn down:
  ```yaml
  artifactory:
    artifactory:
      persistence:
        type: s3-storage-v3-direct
        awsS3V3:
          bucketName: "devtools-artifactory-binaries-342831714456"
          region: "il-central-1"
  ```
- Update the file's top comment block (currently describes the OSS/no-license state) back to
  reflect Pro + license.

**4. Force the rollout after pushing.** ArgoCD's sync marking `Synced`/`Healthy` does **not**
guarantee the running pod picked up the change: several of these fields (image repository is
the exception) only affect a mounted Secret's *contents*, not the pod template's literal
spec, so the StatefulSet controller has no template diff to act on and won't recreate the pod
on its own — this exact gotcha delayed the OSS rollout by several redundant sync/wait cycles
on 2026-07-11. After confirming (via
`kubectl get application -n argocd artifactory -o jsonpath='{.status.sync.revisions}'`) that
ArgoCD has synced the new commits, just force it:
```bash
kubectl delete pod -n artifactory artifactory-0
```
The StatefulSet recreates it from the current template/Secrets. Watch
`kubectl get pod -n artifactory artifactory-0 -o wide` until `9/9 Running` (or `12/12` once
`jfconnect`/`onemodel`/`evidence` are back), then confirm
`kubectl get application -n argocd artifactory -o jsonpath='{.status.health.status}'` reads
`Healthy`.

**5. Xray.** No Xray-side change is needed — `masterKey`/`joinKey` were left untouched
throughout the OSS detour specifically so Access Federation would resume working the moment
Artifactory has a valid Enterprise+ license again.
