# =============================================================================
# Input-variable contract (STUB — GCP design not yet locked; deferred until
# the AWS shape is proven, see Track D README). Mirror the AWS contract once
# the GCP resource design is locked.
# =============================================================================

variable "project_id" {
  description = "GCP project the decoys land in (client's choice)."
  type        = string
}

variable "regions" {
  description = "Region(s) for regional decoy kinds (GCS). IAM/service accounts are project-global."
  type        = list(string)
  default     = ["us-central1"]
}

variable "tracking_label_key" {
  description = "Attribution label key applied to every decoy (should mimic a normal client label)."
  type        = string
}

variable "tracking_label_value" {
  description = "Attribution label value applied to every decoy."
  type        = string
}

variable "lure_labels" {
  description = "Believable operational labels on every decoy. No Cyngular reference."
  type        = map(string)
  default = {
    env   = "prod"
    owner = "legacy-team"
  }
}

# Per-kind { enabled, count, name_prefix } objects to be added when the GCP
# design is locked: service account, GCS bucket, secret manager secret
# (see references/deception-resource-spec.md §GCP).
