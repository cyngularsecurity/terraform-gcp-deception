variable "project_id" {
  description = "GCP project the decoys land in (client's choice)."
  type        = string
}

variable "regions" {
  description = "Regions for regional decoy kinds (GCS, Secret Manager replicas). Default is a single region."
  type        = list(string)
  default     = ["us-central1"]
  validation {
    condition     = length(var.regions) > 0
    error_message = "At least one region is required."
  }
  validation {
    condition     = length(var.regions) == length(toset(var.regions))
    error_message = "regions must not contain duplicates (duplicate regions break GCS fan-out keys and Secret Manager replicas)."
  }
}

variable "tracking_label_key" {
  description = "Label key applied to every decoy. Should mimic a normal client label."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,62}$", var.tracking_label_key))
    error_message = "GCP label keys must be lowercase, start with a letter, ≤63 chars, [a-z0-9_-]."
  }
  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.tracking_label_key))
    error_message = "tracking_label_key must not contain reserved words: cyngular, deception, decoy, honeytoken, bait, trap, observer."
  }
}

variable "tracking_label_value" {
  description = "Label value applied to every decoy."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9_-]{0,63}$", var.tracking_label_value))
    error_message = "GCP label values must be lowercase, ≤63 chars, [a-z0-9_-]."
  }
  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.tracking_label_value))
    error_message = "tracking_label_value must not contain reserved words: cyngular, deception, decoy, honeytoken, bait, trap, observer."
  }
}

variable "service_account" {
  description = "Service Account honeytokens. Optionally attach an IAM Deny policy scoped to the decoy SAs via an org tag (requires roles/iam.denyAdmin + roles/resourcemanager.tagUser — NOT included in roles/owner; grant at org/folder level first) and/or generate a bait JSON key."
  type = object({
    enabled           = optional(bool, false)
    count             = optional(number, 0)
    name_prefix       = optional(string, "")
    generate_key      = optional(bool, false)
    display_name      = optional(string, "")
    iam_deny_policy   = optional(bool, false)
    deny_tag_key_id   = optional(string, "") # tagKeys/NUMERIC_ID — existing org tag key; required when iam_deny_policy = true
    deny_tag_value_id = optional(string, "") # tagValues/NUMERIC_ID — existing org tag value; required when iam_deny_policy = true
  })
  default = {}

  # Deny-policy conditions only support resource.matchTag()/matchTagId() — resource
  # names are NOT valid deny conditions. Each decoy SA is bound to the supplied tag
  # value and the deny rule matches on that tag, scoping it to decoy SAs only.
  validation {
    condition     = !var.service_account.iam_deny_policy || (can(regex("^tagKeys/[0-9]+$", var.service_account.deny_tag_key_id)) && can(regex("^tagValues/[0-9]+$", var.service_account.deny_tag_value_id)))
    error_message = "When iam_deny_policy = true, deny_tag_key_id (tagKeys/NUMERIC_ID) and deny_tag_value_id (tagValues/NUMERIC_ID) must reference an existing org tag key/value. The tag's short names must not contain the reserved words either — they are visible on the SA."
  }

  validation {
    condition     = !(var.service_account.enabled && var.service_account.count > 0 && var.service_account.name_prefix == "")
    error_message = "service_account.name_prefix is required when enabled=true and count > 0."
  }
  validation {
    condition     = var.service_account.count >= 0 && var.service_account.count <= 99
    error_message = "service_account.count must be between 0 and 99."
  }
  # account_id = "${name_prefix}-NN"; GCP requires 6-30 chars total.
  # ≥3-char prefix + 3-char suffix ("-NN") = ≥6 chars; ≤27-char prefix + 3-char suffix = 30 chars.
  validation {
    condition     = var.service_account.name_prefix == "" || can(regex("^[a-z][a-z0-9-]{2,26}$", var.service_account.name_prefix))
    error_message = "service_account.name_prefix must be 3-27 chars, start with a letter, and contain only [a-z0-9-] (combined with the '-NN' suffix the account_id stays within GCP's 6-30 char limit)."
  }
  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.service_account.name_prefix))
    error_message = "service_account.name_prefix must not contain reserved words: cyngular, deception, decoy, honeytoken, bait, trap, observer."
  }
  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.service_account.display_name))
    error_message = "service_account.display_name must not contain reserved words: cyngular, deception, decoy, honeytoken, bait, trap, observer."
  }
}

variable "gcs_bucket" {
  description = "GCS bucket decoys. Uniform BPA enforced, no public IAM, decoy objects inside. Fans out over var.regions."
  type = object({
    enabled     = optional(bool, false)
    count       = optional(number, 0)
    name_prefix = optional(string, "")
    decoy_objects = optional(list(object({
      name    = string
      content = string
    })), [])
  })
  default = {}

  validation {
    condition     = !(var.gcs_bucket.enabled && var.gcs_bucket.count > 0 && var.gcs_bucket.name_prefix == "")
    error_message = "gcs_bucket.name_prefix is required when enabled=true and count > 0."
  }
  validation {
    condition     = var.gcs_bucket.count >= 0 && var.gcs_bucket.count <= 99
    error_message = "gcs_bucket.count must be between 0 and 99."
  }
  # Bucket name = "${name_prefix}-${4-hex}-${idx}-${region}".
  # Worst case: 30 + 1 + 4 + 1 + 2 + 1 + 23 = 62 chars (northamerica-northeast1/2 are the longest region names).
  validation {
    condition     = var.gcs_bucket.name_prefix == "" || can(regex("^[a-z0-9][a-z0-9._-]{0,29}$", var.gcs_bucket.name_prefix))
    error_message = "gcs_bucket.name_prefix must start with a letter or number, contain only [a-z0-9._-], and be ≤30 chars."
  }
  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.gcs_bucket.name_prefix))
    error_message = "gcs_bucket.name_prefix must not contain reserved words: cyngular, deception, decoy, honeytoken, bait, trap, observer."
  }
  # GCS rejects bucket names starting with "goog" or containing "google" — catch at plan, not apply.
  validation {
    condition     = !can(regex("^goog", var.gcs_bucket.name_prefix)) && !can(regex("google", var.gcs_bucket.name_prefix))
    error_message = "gcs_bucket.name_prefix must not start with 'goog' or contain 'google' (GCS bucket-name restriction)."
  }
  validation {
    condition     = length(var.gcs_bucket.decoy_objects) == length(toset([for o in var.gcs_bucket.decoy_objects : o.name]))
    error_message = "gcs_bucket.decoy_objects must have unique names."
  }
  validation {
    condition     = alltrue([for o in var.gcs_bucket.decoy_objects : !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", o.name))])
    error_message = "gcs_bucket.decoy_objects names must not contain reserved words: cyngular, deception, decoy, honeytoken, bait, trap, observer."
  }
  validation {
    condition     = alltrue([for o in var.gcs_bucket.decoy_objects : !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", o.content))])
    error_message = "gcs_bucket.decoy_objects contents must not contain reserved words: cyngular, deception, decoy, honeytoken, bait, trap, observer."
  }
}

variable "secret" {
  description = "Secret Manager decoys. Real-looking fake value, no restrictive IAM. Replicas fan out over var.regions."
  type = object({
    enabled     = optional(bool, false)
    count       = optional(number, 0)
    name_prefix = optional(string, "")
    fake_value  = optional(string, "")
  })
  default = {}

  validation {
    condition     = !(var.secret.enabled && var.secret.count > 0 && var.secret.name_prefix == "")
    error_message = "secret.name_prefix is required when enabled=true and count > 0."
  }
  validation {
    condition     = var.secret.count >= 0 && var.secret.count <= 99
    error_message = "secret.count must be between 0 and 99."
  }
  # secret_id = "${name_prefix}-NN"; Secret Manager allows up to 255 chars.
  validation {
    condition     = var.secret.name_prefix == "" || can(regex("^[a-zA-Z0-9_-]{1,252}$", var.secret.name_prefix))
    error_message = "secret.name_prefix must contain only [a-zA-Z0-9_-] and be ≤252 chars (leaves room for the '-NN' suffix within Secret Manager's 255-char limit)."
  }
  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.secret.name_prefix))
    error_message = "secret.name_prefix must not contain reserved words: cyngular, deception, decoy, honeytoken, bait, trap, observer."
  }
  validation {
    condition     = !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", var.secret.fake_value))
    error_message = "secret.fake_value must not contain reserved words: cyngular, deception, decoy, honeytoken, bait, trap, observer."
  }
}

variable "lure_labels" {
  description = "Believable operational labels applied to every decoy."
  type        = map(string)
  default = {
    env   = "prod"
    owner = "legacy-team"
  }
  validation {
    condition     = alltrue([for k, v in var.lure_labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "GCP labels must be lowercase [a-z0-9_-], ≤63 chars, keys must start with a letter."
  }
  validation {
    condition     = alltrue([for k, v in var.lure_labels : !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", k)) && !can(regex("(?i)(cyngular|deception|decoy|honeytoken|bait|trap|observer)", v))])
    error_message = "lure_labels keys and values must not contain reserved words: cyngular, deception, decoy, honeytoken, bait, trap, observer."
  }
}
