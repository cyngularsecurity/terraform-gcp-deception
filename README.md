# terraform-gcp-deception

Terraform module that plants **inert GCP decoy (honeytoken) resources** into a client environment — the GCP counterpart of [`terraform-aws-deception`](https://github.com/cyngularsecurity/terraform-aws-deception).

## Design

- **Freely reachable, externally-unreachable** — any principal with normal project access can discover the decoys; no public internet access is possible.
- **Inert by policy, lured by name** — IAM Deny policies block the impersonation surface on decoy SAs; GCS buckets enforce uniform access + public-access prevention; secrets carry realistic-looking fake values. Nothing usable is inside.
- **No Cyngular reference anywhere in the environment** — all resource names, labels, and object contents use generic operational vocabulary. A regex validator rejects reserved words (`cyngular`, `deception`, `decoy`, `honeytoken`, `bait`, `trap`, `observer`) from every caller-supplied name field.
- **Attribution = outputs + a caller-supplied tracking label** — the platform registers the outputs to wire up detection; no out-of-band signalling happens inside the module.

## Resource kinds (v1)

| Kind | GCP resource(s) | Scope |
|------|----------------|-------|
| Service Account | `google_service_account` + IAM Deny policy + optional JSON key | project-global |
| GCS Bucket | `google_storage_bucket` + uniform BPA + decoy objects | one bucket per (count × region) |
| Secret Manager Secret | `google_secret_manager_secret` + version | global metadata, per-region replicas |
| Decoy DevOps scripts | `google_storage_bucket` + Python scripts with an embedded honeytoken | one bucket per region |

## Required GCP APIs

Enable these APIs in the target project before applying:

```
iam.googleapis.com
iamcredentials.googleapis.com
storage.googleapis.com
secretmanager.googleapis.com
```

## Usage

This example exercises every capability of the module. For a minimal quick start, drop the `iam_deny_policy`/`deny_tag_*` lines and the bait-key lines — the module then plants inert SAs, buckets, and secrets with no prerequisites beyond the [required APIs](#required-gcp-apis).

```hcl
module "deception" {
  source  = "cyngularsecurity/deception/gcp"

  project_id = "my-gcp-project"            # project the decoys land in
  regions    = ["us-central1", "us-east1"] # fan-out for buckets + secret replicas

  # Applied to every decoy; the platform filters on this pair to find the set.
  tracking_label_key   = "managed-by"
  tracking_label_value = "platform"

  # OPTIONAL — override the believable operational labels on every decoy.
  lure_labels = {
    env         = "prod"
    owner       = "legacy-team"
    cost-center = "infrastructure"
  }

  # Decoy service accounts — inert identities (zero role bindings anywhere).
  service_account = {
    enabled      = true
    count        = 2
    name_prefix  = "admin-svc"             # SA emails: admin-svc-01@..., admin-svc-02@...
    display_name = "Admin Service Account" # OPTIONAL — falls back to name_prefix-NN

    # OPTIONAL - bait credential: a real JSON key that authenticates but can do
    # nothing, planted in a dedicated Secret Manager secret per SA.
    generate_key           = true
    store_key_in_secret    = true
    key_secret_name_prefix = "app-runtime-config" # secrets: app-runtime-config-01, -02

    # OPTIONAL - hard impersonation block (recommended whenever generate_key = true).
    # Requires a one-time org setup — see "Enabling the IAM Deny policy" below.
    iam_deny_policy   = true
    deny_tag_key_id   = "tagKeys/123456789"   # replace with your org tag key ID
    deny_tag_value_id = "tagValues/987654321" # replace with your org tag value ID
  }

  # OPTIONAL + REQUIRES DENY POLICY ABOVE 
  # Decoy DevOps scripts — a "devops-scripts" bucket of realistic Python scripts,
  # each with an embedded honeytoken. 
  decoy_scripts = {
    enabled      = true
    name_prefix  = "devops-scripts"
    script_count = 3            # random project-varied subset of the bundled templates
    token_type   = "gcp_sa_key" # requires generate_key = true above
  }


  # Decoy GCS buckets — discoverable in-project, unreachable from the internet.
  gcs_bucket = {
    enabled     = true
    count       = 1                 # buckets per region
    name_prefix = "finance-exports" # bucket names: finance-exports-<hex>-01-<region>
    decoy_objects = [               # believable contents; reads are the tripwire
      { name = "reports/q4-summary.csv", content = "date,amount\n2024-01-15,142500\n" },
      { name = "backups/service-credentials.json", content = "{\"type\":\"service_account\",\"project_id\":\"legacy-prod\"}" },
    ]
  }

  # Decoy Secret Manager secrets — fake values shaped like real credentials.
  secret = {
    enabled     = true
    count       = 2
    name_prefix = "legacy-api-key" # secret IDs: legacy-api-key-01, -02
    # fake_value = "AKIA..."       # OPTIONAL — omit to auto-generate a random value
  }

  # Opt-in: Data Access audit logging for GCS + Secret Manager — without it (or
  # an equivalent client-side config) reads of the decoys are not logged at all.
  audit_logging = {
    enabled = true
  }
}

output "tracking_label" {
  value = module.deception.tracking_label
}

output "service_account_emails" {
  value = module.deception.service_account_emails
}

output "gcs_bucket_names" {
  value = module.deception.gcs_bucket_names
}

output "secret_ids" {
  value = module.deception.secret_ids
}

# Where the bait keys were planted (store_key_in_secret = true only).
output "service_account_key_secret_ids" {
  value = module.deception.service_account_key_secret_ids
}
```

## Deploying to multiple projects

The module is single-project by design — the input/output schema is kept identical across the AWS/Azure/GCP siblings, and internal fan-out over projects is impossible on the AWS side (providers cannot be looped), so multi-project deployment is the caller's `for_each`, one module instance per project:

```hcl
variable "project_ids" {
  type = list(string)
  default     = ["project-one", "project-two"]
}

module "deception" {
  source   = "cyngularsecurity/deception/gcp"
  for_each = toset(var.project_ids)

  project_id = each.value
  # ... same per-kind config as above
}

output "tracking_label" {
  value = { for p, m in module.deception : p => m.tracking_label }
}

output "service_account_emails" {
  value = { for p, m in module.deception : p => m.service_account_emails }
}

output "gcs_bucket_names" {
  value = { for p, m in module.deception : p => m.gcs_bucket_names }
}

output "secret_ids" {
  value = { for p, m in module.deception : p => m.secret_ids }
}
```

Each instance is fully independent — its own resources and output maps, keyed by project ID at the root — and adding or removing a project never disturbs the other projects' state addresses. See [`examples/multi-project/`](examples/multi-project/) for a complete configuration.

## Enabling the IAM Deny policy (optional)

`iam_deny_policy = true` needs a one-time org setup, because deny-policy conditions can only match org tags. Create the tag once, grant two roles, then pass the numeric IDs to the module:

```bash
# 1. Create an org tag key/value (roles/resourcemanager.tagAdmin). Use ordinary
#    governance names — they are visible on the SA and must not contain a reserved word.
gcloud resource-manager tags keys create service-tier --parent=organizations/YOUR_ORG_ID
gcloud resource-manager tags values create restricted --parent=tagKeys/123456789

# 2. Grant the applying identity: roles/iam.denyAdmin (org/folder) and
#    roles/resourcemanager.tagUser on the tag value.
```

Then set `iam_deny_policy = true`, `deny_tag_key_id`, and `deny_tag_value_id` as shown in [Usage](#usage). Leaving the flag `false` still plants inert SAs (zero role bindings) — it just skips the hard impersonation block.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project_id` | `string` | — | GCP project the decoys land in |
| `regions` | `list(string)` | `["us-central1"]` | Regions for GCS buckets and Secret Manager replicas |
| `tracking_label_key` | `string` | — | Label key applied to every decoy |
| `tracking_label_value` | `string` | — | Label value applied to every decoy |
| `service_account` | `object` | `{}` | Service Account decoy config (see below) |
| `gcs_bucket` | `object` | `{}` | GCS bucket decoy config (see below) |
| `secret` | `object` | `{}` | Secret Manager decoy config (see below) |
| `decoy_scripts` | `object` | `{}` | Decoy DevOps-scripts bucket config (see below) |
| `lure_labels` | `map(string)` | `{env="prod", owner="legacy-team"}` | Believable operational labels on every decoy |
| `audit_logging` | `object` | `{enabled=false}` | Opt-in Data Access audit logging for GCS + Secret Manager — see [Detection wiring](#detection-wiring-data-access-audit-logs) |

### `service_account` object

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `bool` | `false` | Create service account decoys |
| `count` | `number` | `0` | Number of decoy service accounts |
| `name_prefix` | `string` | `""` | Prefix for `account_id` (3-27 chars, `[a-z][a-z0-9-]*`) |
| `display_name` | `string` | `""` | Human-readable name (falls back to `name_prefix-NN`) |
| `generate_key` | `bool` | `false` | Create a bait JSON key for each SA |
| `iam_deny_policy` | `bool` | `false` | Attach a tag-scoped IAM Deny policy blocking the impersonation surface — see note below |
| `deny_tag_key_id` | `string` | `""` | Existing org tag key (`tagKeys/NUMERIC_ID`); required when `iam_deny_policy = true` |
| `deny_tag_value_id` | `string` | `""` | Existing org tag value (`tagValues/NUMERIC_ID`); required when `iam_deny_policy = true` |
| `store_key_in_secret` | `bool` | `false` | Plant each bait key in a dedicated Secret Manager secret (requires `generate_key = true`) |
| `key_secret_name_prefix` | `string` | `""` | Name prefix for the bait-key secrets; required when `store_key_in_secret = true` |

> **Bait-key planting (`store_key_in_secret`):** with `generate_key = true` alone, the key is only surfaced through the module output and the platform must plant it somewhere. With `store_key_in_secret = true` the module plants it itself: each SA's JSON key is stored (decoded, so it reads as a real key file) in a dedicated Secret Manager secret named `{key_secret_name_prefix}-NN`, replicated over `var.regions` and carrying the standard labels. An attacker who finds the secret gets a credential that authenticates but can't do anything — and both touches are auditable: the secret read (`AccessSecretVersion`, needs [Data Access logging](#detection-wiring-data-access-audit-logs)) and the key use (auth events log regardless). Secret IDs are surfaced via `service_account_key_secret_ids` for attribution.
>
> **Org-Policy caveat (`generate_key`):** many organizations enforce the `constraints/iam.disableServiceAccountKeyCreation` Org Policy (it's a CIS-benchmark recommendation), and it can be inherited from the org or folder, so it may apply to some client projects and not others. When enforced, `generate_key = true` fails **at apply** (Terraform cannot detect it at plan) with `Error 400: Key creation is not allowed on this service account`. Options: keep `generate_key = false` for that project, or have an Org Policy administrator (`roles/orgpolicy.policyAdmin`) add a project-level exception before applying. Note the tradeoff cuts both ways — an org that disables key creation everywhere makes a planted key *more* suspicious to a careful attacker, and the SA + impersonation-deny decoy surface still works without any key.

> **`iam_deny_policy` mechanics & permissions:** IAM Deny policies attach at project scope, and their denial conditions only support resource-tag matching (`resource.matchTag`/`matchTagId`) — they cannot target a resource by name. The module therefore binds a caller-supplied org tag value to each decoy SA and scopes the single deny rule to that tag; without the tag scoping, the rule would block impersonation of **every** SA in the project. Requirements before setting the flag to `true`:
>
> - An existing org-level tag key/value (pass their numeric IDs). The tag's short names are visible on the SA — they must not contain the reserved words either.
> - `roles/iam.denyAdmin` (for `iam.denypolicies.create`) — **not** included in `roles/owner`; grant at org or folder level.
> - `roles/resourcemanager.tagUser` on the tag value (to bind it to the SAs).
>
> Without the flag the module still plants inert SAs (no project-level role bindings means no usable permissions for non-owners), but project owners retain implicit `actAs` ability via their own role.
>
> **Bait key without the deny policy:** a generated key is a real, working credential. With `iam_deny_policy = false` the decoy SA's only safeguard is having zero role bindings — a soft guarantee. If the SA ever gains a binding, the distributed key goes live. The module emits a plan-time **warning** (via a `check` block, hence the `>= 1.5` Terraform requirement) when `generate_key = true` and `iam_deny_policy = false`; treat `iam_deny_policy = true` as the intended production posture whenever bait keys are generated.

### `gcs_bucket` object

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `bool` | `false` | Create GCS bucket decoys |
| `count` | `number` | `0` | Bucket instances per region |
| `name_prefix` | `string` | `""` | Bucket name prefix (≤30 chars, `[a-z0-9][a-z0-9._-]*`) |
| `decoy_objects` | `list({name, content})` | `[]` | Objects to create inside each bucket |

### `secret` object

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `bool` | `false` | Create Secret Manager decoys |
| `count` | `number` | `0` | Number of decoy secrets |
| `name_prefix` | `string` | `""` | Prefix for `secret_id` (≤252 chars, `[a-zA-Z0-9_-]`) |
| `fake_value` | `string` | `""` | Secret value to store (module generates a 40-char random string if empty) |

### `decoy_scripts` object

A bucket of realistic Python scripts (`deploy_release.py`, `db_backup_sync.py`, …), each carrying an embedded honeytoken. The module ships the script templates; a **deterministic, project-varied** subset is planted at randomized paths (`ci/`, `tools/`, `internal/jobs/`, …) — stable across applies (zero drift on re-run) but different per project.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `bool` | `false` | Create the decoy-scripts bucket |
| `name_prefix` | `string` | `"devops-scripts"` | Bucket name prefix (same rules as `gcs_bucket.name_prefix`) |
| `script_count` | `number` | `3` | How many of the bundled templates to plant (1–20; capped at the number available) |
| `token_type` | `string` | `"gitlab"` | Embedded credential: `gitlab` (fake `glpat-…`), `aws` (fake `AKIA…` + secret), or `gcp_sa_key` (the module's real bait SA key) |

> **`token_type = gcp_sa_key`** embeds one of the module's actual bait SA keys (round-robined across the decoy SAs), so the honeytoken *authenticates* — the script read **and** the key use both trip detection — but the SA is inert. It requires `service_account.generate_key = true` and `count > 0` (enforced by a resource precondition at plan/apply).
>
> ⚠️ **Set `service_account.iam_deny_policy = true` when using `gcp_sa_key`.** Unlike a plain generated key, this writes the real key into GCS objects in **every regional scripts bucket** (plus state) — many readable copies. With the deny policy off, those copies are safe only because the SA has zero role bindings; if it ever gains one, a live key is scattered across many locations. The hard impersonation block removes that conditional risk. The module emits a plan-time **warning** when `gcp_sa_key` is used without the deny policy. Prefer `gitlab`/`aws` (fake per-instance tokens, no real credential distributed) when you can't attach the deny policy — detection then relies on the bucket-read Data Access log ([enable audit logging](#detection-wiring-data-access-audit-logs)).

## Outputs

| Name | Description |
|------|-------------|
| `tracking_label` | `{key, value}` — the tracking label applied to every decoy |
| `service_account_emails` | Emails of the decoy service accounts |
| `service_account_ids` | Full resource names of the decoy service accounts |
| `service_account_key_ids` | Key IDs of bait SA keys (`generate_key=true` only) |
| `service_account_key_private_keys` | Base64-encoded bait key JSON (sensitive; `generate_key=true` only) |
| `service_account_key_secret_ids` | Secret IDs of the bait-key secrets (`store_key_in_secret=true` only) |
| `service_account_key_secret_names` | Full resource names of the bait-key secrets (`store_key_in_secret=true` only) |
| `gcs_bucket_names` | Names of the decoy GCS buckets |
| `gcs_bucket_urls` | `gs://` URLs of the decoy GCS buckets |
| `decoy_scripts_bucket_names` | Names of the decoy-scripts buckets, keyed by region (`decoy_scripts.enabled` only) |
| `decoy_scripts_object_paths` | Planted script object paths (`decoy_scripts.enabled` only) |
| `secret_ids` | Secret IDs of the decoy Secret Manager secrets |
| `secret_names` | Full resource names of the decoy secrets |

## Identity inertness

Decoy service accounts hold **zero project-level role bindings** — GCP's default-deny means any non-owner principal that discovers the SA cannot use it. When `iam_deny_policy = true` (see the permission note above), each decoy SA is bound to the supplied org tag value and a project-level IAM Deny policy is attached whose single rule matches that tag (`resource.matchTagId`) and blocks:

- `iam.serviceAccounts.actAs`
- `iam.serviceAccounts.getAccessToken`
- `iam.serviceAccounts.signJwt`
- `iam.serviceAccounts.signBlob`
- `iam.serviceAccounts.implicitDelegation`
- `iam.serviceAccounts.getOpenIdToken`

for `principalSet://goog/public:all`. This means even project owners cannot impersonate the decoy SA, while untagged (real) SAs in the project are untouched. Impersonation attempts generate Cloud Audit Log entries. Verify the policy with `gcloud iam policies list --attachment-point=cloudresourcemanager.googleapis.com%2Fprojects%2FPROJECT_ID --kind=denypolicies` — project-level deny policies do **not** appear in `gcloud iam service-accounts get-iam-policy` output.

## Detection wiring (Data Access audit logs)

GCP only logs Admin Activity by default. **Reading a GCS object or accessing a secret version is a Data Access event, which is NOT logged unless Data Access audit logging is enabled** — without it, the GCS, decoy-scripts, and Secret Manager decoys are silent: an attacker can read every decoy object, script, and secret without a single log entry, and the attribution outputs have nothing to match against. (SA impersonation attempts — and the *use* of a `gcp_sa_key` bait credential embedded in a script — are the exception: those log regardless.)

Set `audit_logging = { enabled = true }` to have the module enable `DATA_READ` + `DATA_WRITE` audit logging for `storage.googleapis.com` (when `gcs_bucket` **or** `decoy_scripts` is deployed) and `secretmanager.googleapis.com` (when `secret` is deployed). Before enabling, know the tradeoffs:

- The audit config is **authoritative per service** — it replaces any Data Access config the client already has for these two services in the project.
- It applies **project-wide** (all buckets and secrets, not just decoys) — expect additional log volume and cost in busy projects.

If the client or platform already manages Data Access logging (org policy, existing audit configs), leave this disabled — but confirm it covers both services, or the traps never fire.

## State handling

Terraform state for this module contains the bait SA private keys (when `generate_key = true`), every fake secret value, the real key embedded in `gcp_sa_key` decoy scripts (which also lives in the GCS script objects themselves), and a complete inventory of the decoys — anyone who reads the state can distinguish decoys from real infrastructure, which defeats the deception layer for that client. Treat state access like production-secret access:

- Always use a remote, encrypted, access-controlled backend (e.g. a GCS backend with CMEK and versioning). Never keep local state for real deployments, and never apply from a checkout of this module repo.
- `sensitive = true` on outputs only redacts CLI display; the values are stored in state in plaintext regardless.

## Changing `regions`

Secret Manager replication is immutable: adding or removing a region **destroys and recreates every decoy secret** (same `secret_id`, but version history and creation timestamps reset, and there is a brief window where the secret does not exist). GCS buckets and decoy-scripts buckets in removed regions are destroyed. Plan region changes as a redeployment, not an in-place update.