# Data Access audit logging — the detection wiring for the data-plane decoys.
resource "google_project_iam_audit_config" "storage" {
  count = var.audit_logging.enabled && var.gcs_bucket.enabled && var.gcs_bucket.count > 0 ? 1 : 0

  project = var.project_id
  service = "storage.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_project_iam_audit_config" "secretmanager" {
  count = var.audit_logging.enabled && var.secret.enabled && var.secret.count > 0 ? 1 : 0

  project = var.project_id
  service = "secretmanager.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}
