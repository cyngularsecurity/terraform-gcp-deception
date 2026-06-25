output "tracking_label" {
  description = "The tracking label applied to every decoy, echoed for platform registration."
  value = {
    key   = var.tracking_label_key
    value = var.tracking_label_value
  }
}

# Service Accounts

output "service_account_emails" {
  description = "Emails of the decoy service accounts, keyed by instance index."
  value       = { for k, sa in google_service_account.decoy : k => sa.email }
}

output "service_account_ids" {
  description = "Full resource names of the decoy service accounts, keyed by instance index."
  value       = { for k, sa in google_service_account.decoy : k => sa.name }
}

output "service_account_key_ids" {
  description = "Key IDs of the bait service account JSON keys, keyed by instance index (generate_key=true only)."
  value       = { for k, key in google_service_account_key.decoy : k => key.id }
}

output "service_account_key_private_keys" {
  description = "Base64-encoded private key JSON for the bait SA keys (populated only when generate_key=true). Treat as sensitive."
  value       = { for k, key in google_service_account_key.decoy : k => key.private_key }
  sensitive   = true
}

# ── GCS Buckets

output "gcs_bucket_names" {
  description = "Names of the decoy GCS buckets, keyed by instance index (idx-region)."
  value       = { for k, b in google_storage_bucket.decoy : k => b.name }
}

output "gcs_bucket_urls" {
  description = "Self-links (gs:// URLs) of the decoy GCS buckets, keyed by instance index."
  value       = { for k, b in google_storage_bucket.decoy : k => b.url }
}

# Secret Manager

output "secret_ids" {
  description = "Secret IDs of the decoy Secret Manager secrets, keyed by instance index."
  value       = { for k, s in google_secret_manager_secret.decoy : k => s.secret_id }
}

output "secret_names" {
  description = "Full resource names of the decoy secrets, keyed by instance index."
  value       = { for k, s in google_secret_manager_secret.decoy : k => s.name }
}
