# =============================================================================
# terraform-gcp-deception (DEFERRED SCAFFOLDING)
# GCP counterpart of terraform-aws-deception. Design is NOT yet locked — this
# is a placeholder repo created alongside AWS/Azure. Resource design will
# follow the AWS shape once proven. See references/deception-resource-spec.md
# §GCP for the candidate resource × label × restriction matrix.
# =============================================================================

locals {
  common_labels = merge(
    var.lure_labels,
    { (var.tracking_label_key) = var.tracking_label_value },
  )
}

# Candidate kinds (deferred): Service Account (with IAM Deny policy),
# GCS Bucket (public access prevention enforced), Secret Manager Secret.
