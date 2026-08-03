# terraform-gcp-deception

Terraform module for planting **inert GCP honeytoken resources** in a customer project. It is the GCP sibling of [`terraform-aws-deception`](https://github.com/cyngularsecurity/terraform-aws-deception).

## What It Creates

| Kind | Resources | Detection signal |
|------|-----------|------------------|
| Service accounts | `google_service_account`, optional JSON key, optional IAM Deny policy | SA discovery, key use, impersonation attempts |
| GCS buckets | `google_storage_bucket`, uniform access, public access prevention, decoy objects | Object reads through Data Access logs |
| Secret Manager secrets | `google_secret_manager_secret`, secret versions | `AccessSecretVersion` through Data Access logs |
| DevOps scripts | Regional GCS buckets containing realistic Python scripts with embedded tokens | Script reads; optional GCP SA key use |

## Safety Model

- Decoy service accounts receive **zero role bindings**.
- Optional IAM Deny hardening blocks the SA impersonation surface even for otherwise privileged principals.
- Buckets enforce uniform bucket-level access and public access prevention.
- Secret values and fake script tokens are realistic-looking but not usable.
- Caller-supplied names and labels are validated so they do not expose reserved words such as `cyngular`, `deception`, `decoy`, `honeytoken`, `bait`, `trap`, or `observer`.
- Terraform outputs are the attribution contract. The module does not create out-of-band callbacks.

## Compatibility

| Requirement | Version / scope | Notes |
|-------------|-----------------|-------|
| Terraform | `>= 1.5` | Used for `check` warnings around real bait keys |
| Google provider | `>= 5.0, < 8.0` | IAM, Storage, Secret Manager, audit config, and tag resources |
| Random provider | `>= 3.5, < 4.0` | Stable bucket suffixes and fake token values |
| GCP project | One project per module instance | Use caller-side `for_each` for multiple projects |

## Required APIs

Enable only the APIs needed for the resource types you use:

```text
iam.googleapis.com                  # service accounts, keys, IAM Deny policies
iamcredentials.googleapis.com       # useful for detecting/validating SA credential use
storage.googleapis.com              # GCS bucket and script decoys
secretmanager.googleapis.com        # Secret Manager decoys and stored bait keys
```

For the common deployment path:

```bash
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  storage.googleapis.com \
  secretmanager.googleapis.com \
  --project=YOUR_PROJECT_ID
```

If you enable [IAM Deny hardening](#enabling-the-iam-deny-policy-optional), also enable Cloud Resource Manager:

```bash
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  --project=YOUR_PROJECT_ID
```

## Prerequisites Matrix

| Capability | Enable APIs | Required access / setup | Detection or safety note |
|------------|-------------|-------------------------|--------------------------|
| Service account decoys | `iam.googleapis.com` | `roles/iam.serviceAccountAdmin` on the target project, or equivalent custom permissions | Decoy SAs get zero role bindings. |
| Bait SA keys | `iam.googleapis.com` | `roles/iam.serviceAccountKeyAdmin` on the project or decoy SAs; Org Policy must allow key creation | Fails if `constraints/iam.disableServiceAccountKeyCreation` blocks keys. Use IAM Deny for production bait keys. |
| Store bait keys in Secret Manager | `secretmanager.googleapis.com` | Secret create/version permissions, for example `roles/secretmanager.admin`; requires `service_account.generate_key = true` | Secret reads need Secret Manager Data Access logging. |
| **[IAM Deny hardening](#enabling-the-iam-deny-policy-optional)** | `iam.googleapis.com`, `cloudresourcemanager.googleapis.com` | Org-level: an org tag + `roles/iam.denyAdmin`. See the [dedicated section](#enabling-the-iam-deny-policy-optional). | Strongly recommended for every real bait key. Not covered by `roles/owner`. |
| GCS bucket decoys | `storage.googleapis.com` | Bucket/object create permissions, for example `roles/storage.admin` on the target project | Object reads need Storage Data Access logging. |
| Decoy DevOps scripts | `storage.googleapis.com`; plus `iam.googleapis.com` for `token_type = "gcp_sa_key"` | Storage permissions; plus bait-key prerequisites when embedding a real GCP SA key | Prefer fake `gitlab` or `aws` tokens if IAM Deny cannot be enabled. |
| Secret Manager decoys | `secretmanager.googleapis.com` | Secret create/version permissions, for example `roles/secretmanager.admin` | Secret reads need Secret Manager Data Access logging. |
| Module-managed audit logging | Resource APIs above | Permission to set project IAM policy, for example `roles/iam.securityAdmin`; set `audit_logging = { enabled = true }` | Authoritative per `(project, service)` and can replace existing Data Access audit config. |

> **The prerequisite people miss:** `roles/iam.denyAdmin` is **organization-level** and **not** in `roles/owner`. A project Owner can create every other resource, then fail at the Deny step.
>
> **Fix:** ask an org admin for `roles/iam.denyAdmin`, or set `iam_deny_policy = false` (decoys still work — they just rely on the SA having zero permissions).

## Quick Start

This creates service account, GCS, and Secret Manager decoys without org tag setup or real bait keys.

```hcl
module "deception" {
  source = "cyngularsecurity/deception/gcp"

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
      {
        name    = "reports/q4-summary.csv"
        content = "date,amount\n2024-01-15,142500\n"
      },
      {
        name    = "backups/service-credentials.json"
        content = "{\"type\":\"service_account\",\"project_id\":\"legacy-prod\"}"
      }
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

## Real Bait Key Mode

Use this only when you want a real service account key that authenticates but cannot do anything. For production, enable [IAM Deny hardening](#enabling-the-iam-deny-policy-optional).

```hcl
service_account = {
  enabled                = true
  count                  = 2
  name_prefix            = "admin-svc"
  generate_key           = true
  store_key_in_secret    = true
  key_secret_name_prefix = "app-runtime-config"
  iam_deny_policy        = true
  deny_tag_key_id        = "tagKeys/123456789"
  deny_tag_value_id      = "tagValues/987654321"
}
```

Without `iam_deny_policy = true`, the only thing keeping the key harmless is the SA having zero permissions. Grant that SA a role and the key becomes usable — Terraform warns when you're in this state.

## Decoy Script Tokens

`decoy_scripts.token_type` controls the token embedded in generated Python scripts.

```hcl
decoy_scripts = {
  enabled      = true
  name_prefix  = "devops-scripts"
  script_count = 3
  token_type   = "gitlab" # gitlab | aws | gcp_sa_key
}
```

| Token type | Behavior | Recommendation |
|------------|----------|----------------|
| `gitlab` | Fake `glpat-...` token | Default; safest when IAM Deny is unavailable |
| `aws` | Fake `AKIA...` access key and secret | Same safety profile as `gitlab` |
| `gcp_sa_key` | Embeds one of this module's real bait SA keys | Requires `service_account.generate_key = true` and should use IAM Deny |

## Enabling the IAM Deny Policy (Optional)

**What it is:** a Deny policy makes GCP refuse *all* impersonation of the decoy SA — for everyone, including Owners and Org Admins. An explicit "no" that overrides every "yes".

**Who does what:**

- **Org admin (one-time):** creates the org tag, grants you `roles/iam.denyAdmin`.
- **You (Terraform):** pass the tag IDs; hold `denyAdmin`, `tagUser`, and SA admin.

Setup is one-time. Deny conditions can't name an SA directly, so the module tags each decoy SA and scopes the policy to that tag.

1. Create an org tag key/value.

```bash
gcloud resource-manager tags keys create deny-sa \
  --parent=organizations/ORG_ID

gcloud resource-manager tags values create enabled \
  --parent=tagKeys/TAG_KEY_ID
```

The commands return numeric IDs like `tagKeys/123456789` and `tagValues/987654321`. Pass those exact IDs to:

```hcl
service_account = {
  iam_deny_policy   = true
  deny_tag_key_id   = "tagKeys/123456789"
  deny_tag_value_id = "tagValues/987654321"
}
```

2. Grant the identity running Terraform:

| Role | Scope | Why |
|------|-------|-----|
| `roles/iam.denyAdmin` | Organization | Create/update IAM Deny policies. This role is not included in `roles/owner`. |
| `roles/resourcemanager.tagUser` | Tag value and target resources | Bind the tag value to the decoy service accounts. |
| `roles/iam.serviceAccountAdmin` | Target project | Create service accounts and allow tag binding to those service accounts. |

3. Keep tag names neutral.

Tag short names are visible on the service account. Do not use names that reveal the resource is a decoy.

The Deny rule blocks:

- `iam.serviceAccounts.actAs`
- `iam.serviceAccounts.getAccessToken`
- `iam.serviceAccounts.signJwt`
- `iam.serviceAccounts.signBlob`
- `iam.serviceAccounts.implicitDelegation`
- `iam.serviceAccounts.getOpenIdToken`

## Detection Wiring

GCS object reads, decoy-script reads, and Secret Manager reads are **Data Access** events. They are not logged by default.

Set:

```hcl
audit_logging = {
  enabled = true
}
```

When enabled, the module configures `DATA_READ` and `DATA_WRITE` for `storage.googleapis.com` and/or `secretmanager.googleapis.com` when the corresponding decoys are enabled. This setting is authoritative for each `(project, service)`, so leave it disabled if the customer or platform already manages Data Access audit logging.

## Multiple Projects

The module is intentionally single-project. Deploy to many projects with caller-side `for_each`:

```hcl
variable "project_ids" {
  type    = list(string)
  default = ["project-one", "project-two"]
}

module "deception" {
  source   = "cyngularsecurity/deception/gcp"
  for_each = toset(var.project_ids)

  project_id = each.value
  # same per-kind config as the single-project example
}

output "service_account_emails" {
  value = { for p, m in module.deception : p => m.service_account_emails }
}
```

See [`examples/multi-project/`](examples/multi-project/) for a complete configuration.

## State Handling

Treat Terraform state like production-secret access. It can contain generated bait keys, fake secret values, embedded script credentials, and the full decoy inventory.

Use a remote, encrypted, access-controlled backend. `sensitive = true` only redacts CLI output; values still live in state.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project_id` | `string` | - | GCP project the decoys land in |
| `regions` | `list(string)` | `["us-central1"]` | Regions for buckets and Secret Manager replicas |
| `tracking_label_key` | `string` | - | Label key applied to every decoy |
| `tracking_label_value` | `string` | - | Label value applied to every decoy |
| `service_account` | `object` | `{}` | Service account decoy config |
| `gcs_bucket` | `object` | `{}` | GCS bucket decoy config |
| `secret` | `object` | `{}` | Secret Manager decoy config |
| `decoy_scripts` | `object` | `{}` | Decoy script bucket config |
| `lure_labels` | `map(string)` | `{env="prod", owner="legacy-team"}` | Operational labels on every decoy |
| `audit_logging` | `object` | `{enabled=false}` | Opt-in Data Access audit logging |

### Object Fields

| Object | Field | Default | Description |
|--------|-------|---------|-------------|
| `service_account` | `enabled` | `false` | Create service account decoys |
| `service_account` | `count` | `0` | Number of decoy SAs |
| `service_account` | `name_prefix` | `""` | Prefix for `account_id` |
| `service_account` | `display_name` | `""` | Human-readable name |
| `service_account` | `generate_key` | `false` | Create a bait JSON key per SA |
| `service_account` | `iam_deny_policy` | `false` | Attach tag-scoped IAM Deny hardening |
| `service_account` | `deny_tag_key_id` | `""` | Existing org tag key ID, `tagKeys/NUMERIC_ID` |
| `service_account` | `deny_tag_value_id` | `""` | Existing org tag value ID, `tagValues/NUMERIC_ID` |
| `service_account` | `store_key_in_secret` | `false` | Store each bait key in Secret Manager |
| `service_account` | `key_secret_name_prefix` | `""` | Secret name prefix for stored bait keys |
| `gcs_bucket` | `enabled` | `false` | Create bucket decoys |
| `gcs_bucket` | `count` | `0` | Buckets per region |
| `gcs_bucket` | `name_prefix` | `""` | Bucket name prefix |
| `gcs_bucket` | `decoy_objects` | `[]` | Objects created in each bucket |
| `secret` | `enabled` | `false` | Create Secret Manager decoys |
| `secret` | `count` | `0` | Number of decoy secrets |
| `secret` | `name_prefix` | `""` | Prefix for `secret_id` |
| `secret` | `fake_value` | `""` | Explicit fake value; random if empty |
| `decoy_scripts` | `enabled` | `false` | Create script buckets |
| `decoy_scripts` | `name_prefix` | `"devops-scripts"` | Script bucket name prefix |
| `decoy_scripts` | `script_count` | `3` | Number of scripts to plant |
| `decoy_scripts` | `token_type` | `"gitlab"` | `gitlab`, `aws`, or `gcp_sa_key` |

## Outputs

| Name | Description |
|------|-------------|
| `tracking_label` | `{key, value}` applied to every decoy |
| `service_account_emails` | Emails of decoy SAs |
| `service_account_ids` | Full resource names of decoy SAs |
| `service_account_key_ids` | Bait key IDs |
| `service_account_key_private_keys` | Base64-encoded bait key JSON, sensitive |
| `service_account_key_secret_ids` | Secret IDs for stored bait keys |
| `service_account_key_secret_names` | Full Secret Manager names for stored bait keys |
| `gcs_bucket_names` | Decoy bucket names |
| `gcs_bucket_urls` | `gs://` URLs |
| `decoy_scripts_bucket_names` | Script bucket names by region |
| `decoy_scripts_object_paths` | Planted script object paths |
| `secret_ids` | Secret IDs |
| `secret_names` | Full Secret Manager names |
