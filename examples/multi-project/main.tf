# Deploys the decoy set into several projects from one root configuration.
#
# The module is single-project by design (input/output schema is shared with
# the AWS and Azure siblings, which cannot fan out over accounts internally) —
# multi-project is the caller's for_each, one module instance per project.
# Each instance is independent: its own resources, its own output maps, and
# removal of one project never disturbs the others' state addresses.

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 8.0"
    }
  }
}

provider "google" {
  region = "us-central1"
}

variable "project_ids" {
  description = "GCP projects to deploy decoys into."
  type        = list(string)
  default     = ["my-project-one", "my-project-two"]
}

module "deception" {
  source   = "cyngularsecurity/deception/gcp"
  version  = "~> 0.0"
  for_each = toset(var.project_ids)

  project_id = each.value
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

# Outputs keyed by project ID, each holding the module's per-instance map.

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
