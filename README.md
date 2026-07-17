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

## Compatibility / Requirements

| Requirement | Version / scope | Notes |
|-------------|-----------------|-------|
| Terraform | `>= 1.5` | Required for `check` blocks that emit bait-key safety warnings |
| Google provider | `>= 5.0, < 8.0` | Creates IAM, Storage, Secret Manager, audit config, and tag resources |
| Random provider | `>= 3.5, < 4.0` | Generates stable bucket suffixes and fake secret/token values |
| GCP project | One project per module instance | Use caller-side `for_each` for multi-project deployment |

## Required GCP APIs

Enable these APIs in the target project before applying:

```
iam.googleapis.com
iamcredentials.googleapis.com
storage.googleapis.com
secretmanager.googleapis.com
```

## Prerequisites Matrix

| Capability | Required APIs | Required permissions / setup | Notes |
|------------|---------------|------------------------------|-------|
| Service account decoys | `iam.googleapis.com` | Permission to create service accounts in the target project | No role bindings are created for the decoy SAs |
| Bait SA keys | `iam.googleapis.com` | Permission to create service account keys; Org Policy must allow key creation | Fails at apply if `constraints/iam.disableServiceAccountKeyCreation` is enforced |
| IAM Deny hardening | `iam.googleapis.com` | Existing org tag key/value, `roles/iam.denyAdmin`, and `roles/resourcemanager.tagUser` on the tag value | Recommended whenever real bait SA keys are generated |
| GCS bucket decoys | `storage.googleapis.com` | Permission to create buckets and objects | Bucket reads require Data Access audit logging for detection |
| Secret Manager decoys | `secretmanager.googleapis.com` | Permission to create secrets, versions, and regional replicas | Secret reads require Data Access audit logging for detection |
| Decoy DevOps scripts | `storage.googleapis.com` plus `iam.googleapis.com` when `token_type = "gcp_sa_key"` | Permission to create buckets and objects; bait key prerequisites when embedding a real SA key | Fake `gitlab`/`aws` tokens avoid distributing a real credential |
| Module-managed audit logging | Service-specific APIs above | Permission to manage project IAM audit config | Authoritative per service; can replace existing Data Access audit config |

## Usage

### Minimal quick start

This plants inert service accounts, GCS buckets, and Secret Manager secrets with no org-tag or bait-key setup. Enable audit logging here only if this module should manage Data Access audit config for the project.

```hcl
module "deception" {
  source  = "cyngularsecurity/deception/gcp"

  project_id = "my-gcp-project"
  regions    = ["us-central1", "us-east1"]

  tracking_label_key   = "managed-by"
  tracking_label_value = "platform"

  service_account = {
    enabled     = true
    count       = 2
    name_prefix = "admin-svc"
  }

  gcs_bucket = {
    enabled     = true
    count       = 1
    name_prefix = "finance-exports"
    decoy_objects = [
      { name = "reports/q4-summary.csv", content = "date,amount\n2024-01-15,142500\n" },
      { name = "backups/service-credentials.json", content = "{\"type\":\"service_account\",\"project_id\":\"legacy-prod\"}" },
    ]
  }

  secret = {
    enabled     = true
    count       = 2
    name_prefix = "legacy-api-key"
  }

  audit_logging = {
    enabled = true
  }
}
```

### Decoy script token examples

`decoy_scripts.token_type` controls what credential shape is embedded into the generated Python scripts. Use `gitlab` or `aws` when you want fake tokens that only trip on script/object reads. Use `gcp_sa_key` when you want the embedded credential itself to authenticate and trip on key use too.

Fake GitLab token, the default:

```hcl
decoy_scripts = {
  enabled      = true
  name_prefix  = "devops-scripts"
  script_count = 3
  token_type   = "gitlab"
}
```

Fake AWS access key and secret:

```hcl
decoy_scripts = {
  enabled      = true
  name_prefix  = "deployment-tools"
  script_count = 5
  token_type   = "aws"
}
```

Real bait GCP service account key:

```hcl
service_account = {
  enabled           = true
  count             = 2
  name_prefix       = "admin-svc"
  generate_key      = true
  iam_deny_policy   = true
  deny_tag_key_id   = "tagKeys/123456789"
  deny_tag_value_id = "tagValues/987654321"
}

decoy_scripts = {
  enabled      = true
  name_prefix  = "devops-scripts"
  script_count = 3
  token_type   = "gcp_sa_key"
}
```

`gcp_sa_key` requires `service_account.generate_key = true` and at least one service account. Keep `iam_deny_policy = true` for this mode because it writes a real key into every regional scripts bucket.

### Full production example

This example exercises every capability of the module, including bait-key planting, IAM Deny hardening, and decoy DevOps scripts.

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
    # Requires a one-time org setup — DenyAdmin role + see "Enabling the IAM Deny policy" below.
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


## Identity inertness

Decoy service accounts hold **zero project-level role bindings** — GCP's default-deny means any non-owner principal that discovers the SA cannot use it. When `iam_deny_policy = true` (see the permission note above), each decoy SA is bound to the supplied org tag value and a project-level IAM Deny policy is attached whose single rule matches that tag (`resource.matchTagId`) and blocks:

- `iam.serviceAccounts.actAs`
- `iam.serviceAccounts.getAccessToken`
- `iam.serviceAccounts.signJwt`
- `iam.serviceAccounts.signBlob`
- `iam.serviceAccounts.implicitDelegation`
- `iam.serviceAccounts.getOpenIdToken`

## Detection wiring (Data Access audit logs)

GCS object reads, decoy-script reads, and Secret Manager reads are **Data Access** events, not Admin Activity. Enable Data Access logging yourself or set `audit_logging = { enabled = true }`; otherwise those decoys can be read silently. SA impersonation attempts and `gcp_sa_key` use are logged separately.

When enabled, the module configures `DATA_READ` + `DATA_WRITE` for `storage.googleapis.com` and/or `secretmanager.googleapis.com`. 

## State handling

Treat Terraform state like production-secret access. It contains generated bait keys, fake secret values, embedded script credentials, and the full decoy inventory.

Use a remote, encrypted, access-controlled backend for real deployments. `sensitive = true` only redacts CLI output; values still live in state.

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
