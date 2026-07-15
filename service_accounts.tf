# Defense-in-depth warning: a bait key is a real, working credential. The only
# thing keeping the decoy SA inert is "zero role bindings" unless the tag-scoped
# deny policy is attached. Generating a key WITHOUT the deny policy is the
# riskiest combination — if the SA ever gains a binding, the distributed key
# becomes live. This warns (does not block: the deny policy needs org-level
# roles/iam.denyAdmin + tagUser that many projects cannot grant).
check "bait_key_without_deny_policy" {
  assert {
    condition     = !(var.service_account.generate_key && !var.service_account.iam_deny_policy)
    error_message = "service_account.generate_key = true without iam_deny_policy = true: the bait SA key is a real credential protected only by the SA having zero role bindings. Set iam_deny_policy = true (needs roles/iam.denyAdmin + roles/resourcemanager.tagUser and an org tag) for a hard impersonation block, or accept the soft guarantee deliberately."
  }
}

resource "google_service_account" "decoy" {
  for_each = local.sa_keys

  project      = var.project_id
  account_id   = "${var.service_account.name_prefix}-${each.key}"
  display_name = var.service_account.display_name != "" ? var.service_account.display_name : "${var.service_account.name_prefix}-${each.key}"
}

resource "google_service_account_key" "decoy" {
  for_each = var.service_account.generate_key ? local.sa_keys : toset([])

  service_account_id = google_service_account.decoy[each.key].name
}

resource "google_secret_manager_secret" "sa_key" {
  for_each = var.service_account.generate_key && var.service_account.store_key_in_secret ? local.sa_keys : toset([])

  project   = var.project_id
  secret_id = "${var.service_account.key_secret_name_prefix}-${each.key}"

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

resource "google_secret_manager_secret_version" "sa_key" {
  for_each = var.service_account.generate_key && var.service_account.store_key_in_secret ? local.sa_keys : toset([])

  secret      = google_secret_manager_secret.sa_key[each.key].id
  secret_data = base64decode(google_service_account_key.decoy[each.key].private_key)
}

# IAM Deny policy — scoped to the decoy SAs via an org tag.
resource "google_tags_tag_binding" "sa_deny_scope" {
  for_each = var.service_account.iam_deny_policy ? local.sa_keys : toset([])

  parent    = "//iam.googleapis.com/projects/${var.project_id}/serviceAccounts/${google_service_account.decoy[each.key].unique_id}"
  tag_value = var.service_account.deny_tag_value_id
}

resource "google_iam_deny_policy" "sa_deny" {
  count = var.service_account.enabled && var.service_account.count > 0 && var.service_account.iam_deny_policy ? 1 : 0

  parent = urlencode("cloudresourcemanager.googleapis.com/projects/${var.project_id}")
  name   = "${var.service_account.name_prefix}-sa-deny"

  rules {
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
        title      = "scoped-service-access"
        expression = "resource.matchTagId('${var.service_account.deny_tag_key_id}', '${var.service_account.deny_tag_value_id}')"
      }
    }
  }

  depends_on = [google_tags_tag_binding.sa_deny_scope]
}
