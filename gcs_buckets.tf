# Stable 4-hex suffix scoped to this prefix+project so bucket names are globally
# unique without embedding the full project ID (which can be long).
resource "random_id" "gcs_suffix" {
  count       = var.gcs_bucket.enabled && var.gcs_bucket.count > 0 ? 1 : 0
  byte_length = 2
  keepers = {
    name_prefix = var.gcs_bucket.name_prefix
    project_id  = var.project_id
  }
}

resource "google_storage_bucket" "decoy" {
  for_each = local.gcs_pairs

  project  = var.project_id
  name     = "${var.gcs_bucket.name_prefix}-${random_id.gcs_suffix[0].hex}-${each.key}"
  location = each.value.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  labels = local.common_labels
}

resource "google_storage_bucket_object" "decoy" {
  for_each = local.gcs_object_instances

  bucket  = google_storage_bucket.decoy[each.value.bucket_key].name
  name    = each.value.obj.name
  content = each.value.obj.content
}
