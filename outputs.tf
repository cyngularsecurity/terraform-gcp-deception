output "tracking_label" {
  description = "The tracking label applied to every decoy, echoed for platform registration."
  value = {
    key   = var.tracking_label_key
    value = var.tracking_label_value
  }
}

# Service Accounts

output "service_account_emails" {
  description = "Emails of the decoy service accounts."
  value       = [for k, sa in google_service_account.decoy : sa.email]
}

output "service_account_ids" {
  description = "Full resource names of the decoy service accounts (projects/{PROJECT}/serviceAccounts/{EMAIL})."
  value       = [for k, sa in google_service_account.decoy : sa.name]
}

output "service_account_key_ids" {
  description = "Key IDs of the bait service account JSON keys (populated only when generate_key=true)."
  value       = [for k, key in google_service_account_key.decoy : key.id]
}

output "service_account_key_private_keys" {
  description = "Base64-encoded private key JSON for the bait SA keys (populated only when generate_key=true). Treat as sensitive."
  value       = { for k, key in google_service_account_key.decoy : k => key.private_key }
  sensitive   = true
}

# ── GCS Buckets

output "gcs_bucket_names" {
  description = "Names of the decoy GCS buckets."
  value       = [for k, b in google_storage_bucket.decoy : b.name]
}

output "gcs_bucket_urls" {
  description = "Self-links (gs:// URLs) of the decoy GCS buckets."
  value       = [for k, b in google_storage_bucket.decoy : b.url]
}

# Secret Manager

output "secret_ids" {
  description = "Secret IDs of the decoy Secret Manager secrets."
  value       = [for k, s in google_secret_manager_secret.decoy : s.secret_id]
}

output "secret_names" {
  description = "Full resource names of the decoy secrets (projects/{PROJECT}/secrets/{ID})."
  value       = [for k, s in google_secret_manager_secret.decoy : s.name]
}
