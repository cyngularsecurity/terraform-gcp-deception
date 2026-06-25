# Generated when fake_value is not provided; looks like a 40-char API key.
resource "random_password" "secret" {
  for_each = local.secret_keys
  length   = 40
  special  = false
}

resource "google_secret_manager_secret" "decoy" {
  for_each  = local.secret_keys
  project   = var.project_id
  secret_id = "${var.secret.name_prefix}-${each.key}"

  replication {
    user_managed {
      dynamic "replicas" {
        for_each = var.regions
        content {
          location = replicas.value
        }
      }
    }
  }

  labels = local.common_labels
}

resource "google_secret_manager_secret_version" "decoy" {
  for_each = local.secret_keys

  secret      = google_secret_manager_secret.decoy[each.key].id
  secret_data = var.secret.fake_value != "" ? var.secret.fake_value : random_password.secret[each.key].result
}
