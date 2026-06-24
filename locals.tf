locals {
  common_labels = merge(
    var.lure_labels,
    { (var.tracking_label_key) = var.tracking_label_value },
  )

  sa_keys = var.service_account.enabled && var.service_account.count > 0 ? toset([
    for i in range(var.service_account.count) : format("%02d", i + 1)
  ]) : toset([])

  gcs_pairs = var.gcs_bucket.enabled && var.gcs_bucket.count > 0 ? {
    for pair in setproduct(
      [for i in range(var.gcs_bucket.count) : format("%02d", i + 1)],
      var.regions
    ) : "${pair[0]}-${pair[1]}" => {
      idx    = pair[0]
      region = pair[1]
    }
  } : {}

  gcs_object_instances = var.gcs_bucket.enabled && length(var.gcs_bucket.decoy_objects) > 0 ? {
    for pair in setproduct(
      keys(local.gcs_pairs),
      range(length(var.gcs_bucket.decoy_objects))
    ) : "${pair[0]}::${var.gcs_bucket.decoy_objects[pair[1]].name}" => {
      bucket_key = pair[0]
      obj        = var.gcs_bucket.decoy_objects[pair[1]]
    }
  } : {}

  secret_keys = var.secret.enabled && var.secret.count > 0 ? toset([
    for i in range(var.secret.count) : format("%02d", i + 1)
  ]) : toset([])
}