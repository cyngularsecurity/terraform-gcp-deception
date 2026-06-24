terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "us-central1"
}

variable "project_id" {
  description = "GCP project to deploy decoys into."
  type        = string
}

module "deception" {
  source  = "cyngularsecurity/deception/gcp"
  version = "~> 1.0"

  project_id = var.project_id
  regions    = ["us-central1", "us-east1"]

  tracking_label_key   = "managed-by"
  tracking_label_value = "platform"

  lure_labels = {
    env         = "prod"
    owner       = "legacy-team"
    cost-center = "infrastructure"
  }

  service_account = {
    enabled      = true
    count        = 2
    name_prefix  = "admin-svc"
    display_name = "Admin Service Account"
    generate_key = false
  }

  gcs_bucket = {
    enabled     = true
    count       = 1
    name_prefix = "finance-exports"
    decoy_objects = [
      {
        name    = "reports/q4-summary.csv"
        content = "date,amount,description\n2024-01-15,142500.00,Annual revenue\n2024-03-31,98000.00,Q1 adjustment\n"
      },
      {
        name    = "backups/service-credentials.json"
        content = "{\"type\":\"service_account\",\"project_id\":\"legacy-prod\",\"client_email\":\"pipeline-svc@legacy-prod.iam.gserviceaccount.com\"}"
      },
    ]
  }

  secret = {
    enabled     = true
    count       = 2
    name_prefix = "legacy-api-key"
    fake_value  = ""
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
