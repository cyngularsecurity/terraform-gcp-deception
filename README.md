# terraform-gcp-deception

Terraform module that plants **inert GCP decoy (honeytoken) resources** into a client environment — the GCP counterpart of [`terraform-aws-deception`](https://github.com/cyngularsecurity/terraform-aws-deception).

## Design

- **Freely reachable, externally-unreachable** — any principal with normal project access can discover the decoys; no public internet access is possible.
- **Inert by policy, lured by name** — IAM Deny policies block the impersonation surface on decoy SAs; GCS buckets enforce uniform access + public-access prevention; secrets carry realistic-looking fake values. Nothing usable is inside.
- **No Cyngular reference anywhere in the environment** — all resource names, labels, and object contents use generic operational vocabulary. A regex validator rejects reserved words (`cyngular`, `deception`, `decoy`, `honeytoken`, `bait`, `trap`, `token`) from every caller-supplied name field.
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
  version = "~> 1.0"

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

### `service_account` object

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `bool` | `false` | Create service account decoys |
| `count` | `number` | `0` | Number of decoy service accounts |
| `name_prefix` | `string` | `""` | Prefix for `account_id` (3-27 chars, `[a-z][a-z0-9-]*`) |
| `display_name` | `string` | `""` | Human-readable name (falls back to `name_prefix-NN`) |
| `generate_key` | `bool` | `false` | Create a bait JSON key for each SA |
| `iam_deny_policy` | `bool` | `false` | Attach an IAM Deny policy blocking the impersonation surface — see note below |

> **`iam_deny_policy` permission note:** Creating deny policies requires `iam.denypolicies.create`, which is part of `roles/iam.denyAdmin`. This role is **not** included in `roles/owner` and must be granted at the organization or folder level before setting this flag to `true`. Without it the module still plants inert SAs (no project-level role bindings means no usable permissions for non-owners), but project owners retain implicit `actAs` ability via their own role.

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

Decoy service accounts hold **zero project-level role bindings** — GCP's default-deny means any non-owner principal that discovers the SA cannot use it. When `iam_deny_policy = true` (requires `roles/iam.denyAdmin` on the project/folder/org — see above), an IAM Deny policy is also attached that additionally blocks:

- `iam.serviceAccounts.actAs`
- `iam.serviceAccounts.getAccessToken`
- `iam.serviceAccounts.signJwt`
- `iam.serviceAccounts.signBlob`
- `iam.serviceAccounts.implicitDelegation`
- `iam.serviceAccounts.getOpenIdToken`

for `principalSet://goog/public:all`. This means even project owners cannot impersonate the decoy SA. Any attempt generates a Cloud Audit Log entry.

## Releasing

Pushes to `main` trigger `.github/workflows/publish_tf_module.yml` (auto `vX.Y.Z` tag + release). The [Terraform Registry](https://registry.terraform.io) auto-publishes new tags once the repo is connected (one-time UI step).
