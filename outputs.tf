# Attribution outputs (STUB) — created resource IDs/emails per kind + tracking
# label, to be filled when the GCP resources land.

output "tracking_label" {
  description = "The tracking label applied to every decoy, echoed for platform registration."
  value = {
    key   = var.tracking_label_key
    value = var.tracking_label_value
  }
}
