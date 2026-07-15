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

## Usage

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
    ]
  }

  secret = {
    enabled     = true
    count       = 2
    name_prefix = "legacy-api-key"
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
```

## Deploying to multiple projects

The module is single-project by design — the input/output schema is kept identical across the AWS/Azure/GCP siblings, and internal fan-out over projects is impossible on the AWS side (providers cannot be looped), so multi-project deployment is the caller's `for_each`, one module instance per project:

```hcl
variable "project_ids" {
  type = list(string)
}

module "deception" {
  source   = "cyngularsecurity/deception/gcp"
  for_each = toset(var.project_ids)

  project_id = each.value
  # ... same per-kind config as above
}

output "secret_ids" {
  value = { for p, m in module.deception : p => m.secret_ids }
}
```

Each instance is fully independent — its own resources and output maps, keyed by project ID at the root — and adding or removing a project never disturbs the other projects' state addresses. See [`examples/multi-project/`](examples/multi-project/) for a complete configuration.

## Required GCP APIs

Enable these APIs in the target project before applying:

```
iam.googleapis.com
iamcredentials.googleapis.com
storage.googleapis.com
secretmanager.googleapis.com
```

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

> **`iam_deny_policy` mechanics & permissions:** IAM Deny policies attach at project scope, and their denial conditions only support resource-tag matching (`resource.matchTag`/`matchTagId`) — they cannot target a resource by name. The module therefore binds a caller-supplied org tag value to each decoy SA and scopes the single deny rule to that tag; without the tag scoping, the rule would block impersonation of **every** SA in the project. Requirements before setting the flag to `true`:
>
> - An existing org-level tag key/value (pass their numeric IDs). The tag's short names are visible on the SA — they must not contain the reserved words either.
> - `roles/iam.denyAdmin` (for `iam.denypolicies.create`) — **not** included in `roles/owner`; grant at org or folder level.
> - `roles/resourcemanager.tagUser` on the tag value (to bind it to the SAs).
>
> Without the flag the module still plants inert SAs (no project-level role bindings means no usable permissions for non-owners), but project owners retain implicit `actAs` ability via their own role.

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

## Outputs

| Name | Description |
|------|-------------|
| `tracking_label` | `{key, value}` — the tracking label applied to every decoy |
| `service_account_emails` | Emails of the decoy service accounts |
| `service_account_ids` | Full resource names of the decoy service accounts |
| `service_account_key_ids` | Key IDs of bait SA keys (`generate_key=true` only) |
| `service_account_key_private_keys` | Base64-encoded bait key JSON (sensitive; `generate_key=true` only) |
| `gcs_bucket_names` | Names of the decoy GCS buckets |
| `gcs_bucket_urls` | `gs://` URLs of the decoy GCS buckets |
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

GCP only logs Admin Activity by default. **Reading a GCS object or accessing a secret version is a Data Access event, which is NOT logged unless Data Access audit logging is enabled** — without it, the GCS and Secret Manager decoys are silent: an attacker can read every decoy object and secret without a single log entry, and the attribution outputs have nothing to match against. (SA impersonation attempts are the exception — those log regardless.)

Set `audit_logging = { enabled = true }` to have the module enable `DATA_READ` + `DATA_WRITE` audit logging for `storage.googleapis.com` and `secretmanager.googleapis.com` (each only when that decoy kind is deployed). Before enabling, know the tradeoffs:

- The audit config is **authoritative per service** — it replaces any Data Access config the client already has for these two services in the project.
- It applies **project-wide** (all buckets and secrets, not just decoys) — expect additional log volume and cost in busy projects.

If the client or platform already manages Data Access logging (org policy, existing audit configs), leave this disabled — but confirm it covers both services, or the traps never fire.

## State handling

Terraform state for this module contains the bait SA private keys (when `generate_key = true`), every fake secret value, and a complete inventory of the decoys — anyone who reads the state can distinguish decoys from real infrastructure, which defeats the deception layer for that client. Treat state access like production-secret access:

- Always use a remote, encrypted, access-controlled backend (e.g. a GCS backend with CMEK and versioning). Never keep local state for real deployments, and never apply from a checkout of this module repo.
- `sensitive = true` on outputs only redacts CLI display; the values are stored in state in plaintext regardless.

## Changing `regions`

Secret Manager replication is immutable: adding or removing a region **destroys and recreates every decoy secret** (same `secret_id`, but version history and creation timestamps reset, and there is a brief window where the secret does not exist). GCS buckets in removed regions are destroyed. Plan region changes as a redeployment, not an in-place update.