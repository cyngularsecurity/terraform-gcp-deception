resource "google_service_account" "decoy" {
  for_each = local.sa_keys

  project      = var.project_id
  account_id   = "${var.service_account.name_prefix}-${each.key}"
  display_name = var.service_account.display_name != "" ? var.service_account.display_name : "${var.service_account.name_prefix}-${each.key}"
  # GCP Service Accounts do not support labels via the Terraform resource or the SA API.
  # Labels are applied to GCS buckets and secrets; SAs are identified via service_account_emails output.
}

# Bait key — optional JSON credential file planted in the environment as lure.

resource "google_service_account_key" "decoy" {
  for_each = var.service_account.generate_key ? local.sa_keys : toset([])

  service_account_id = google_service_account.decoy[each.key].name
}

# IAM Deny policy
resource "google_iam_deny_policy" "sa_deny" {
  count = var.service_account.enabled && var.service_account.count > 0 && var.service_account.iam_deny_policy ? 1 : 0

  parent = urlencode("cloudresourcemanager.googleapis.com/projects/${var.project_id}")
  name   = "${var.service_account.name_prefix}-sa-deny"

  dynamic "rules" {
    for_each = google_service_account.decoy
    content {
      deny_rule {
        denied_principals = ["principalSet://goog/public:all"]
        denied_permissions = [
          "iam.googleapis.com/serviceAccounts.actAs",
          "iam.googleapis.com/serviceAccounts.getAccessToken",
          "iam.googleapis.com/serviceAccounts.signJwt",
          "iam.googleapis.com/serviceAccounts.signBlob",
          "iam.googleapis.com/serviceAccounts.implicitDelegation",
          "iam.googleapis.com/serviceAccounts.getOpenIdToken",
        ]
        denial_condition {
          title      = rules.key
          expression = "resource.name == \"//iam.googleapis.com/${rules.value.name}\""
        }
      }
    }
  }
}
