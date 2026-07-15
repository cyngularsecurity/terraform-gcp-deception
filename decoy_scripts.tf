# Decoy DevOps scripts — a "devops-scripts" bucket of realistic Python scripts, each carrying an embedded honeytoken

# token_type = gcp_sa_key writes the REAL bait key into GCS objects in every
# regional scripts bucket — many more readable copies than plain generate_key.
# Without the deny policy the only thing keeping those copies safe is the SA
# having zero bindings; warn (do not block — the deny policy needs org perms).
check "gcp_sa_key_script_without_deny_policy" {
  assert {
    condition     = !(var.decoy_scripts.enabled && var.decoy_scripts.token_type == "gcp_sa_key" && !var.service_account.iam_deny_policy)
    error_message = "decoy_scripts.token_type = gcp_sa_key embeds the real bait SA key into GCS objects across every regional scripts bucket (plus state). With iam_deny_policy = false the SA is inert only by virtue of zero role bindings — if it ever gains one, a live key is now scattered across many readable locations. Set service_account.iam_deny_policy = true so the hard impersonation block makes the wide distribution safe, or use token_type = gitlab/aws (fake tokens) instead."
  }
}

locals {
  script_templates = var.decoy_scripts.enabled ? fileset("${path.module}/templates/scripts", "*.py.tftpl") : toset([])

  _scripts_ranked = [
    for f in local.script_templates :
    format("%s|%s", md5("${var.project_id}-${var.decoy_scripts.name_prefix}-${f}"), f)
  ]
  _scripts_sorted  = [for pair in sort(local._scripts_ranked) : element(split("|", pair), 1)]
  scripts_selected = slice(local._scripts_sorted, 0, min(var.decoy_scripts.script_count, length(local._scripts_sorted)))

  script_path_prefixes = ["", "ci/", "tools/", "scripts/deploy/", "internal/jobs/"]
  script_paths = {
    for f in local.scripts_selected : f =>
    "${local.script_path_prefixes[parseint(substr(md5("${var.project_id}-${f}"), 0, 6), 16) % length(local.script_path_prefixes)]}${trimsuffix(f, ".tftpl")}"
  }

  _sa_key_list = sort(tolist(local.sa_keys))
  script_sa_key = var.decoy_scripts.enabled && var.decoy_scripts.token_type == "gcp_sa_key" && length(local._sa_key_list) > 0 ? {
    for i, f in local.scripts_selected : f => local._sa_key_list[i % length(local._sa_key_list)]
  } : {}

  script_credentials = {
    for f in local.scripts_selected : f => (
      var.decoy_scripts.token_type == "gitlab" ?
      "GITLAB_TOKEN = \"glpat-${try(random_string.script_token[f].result, "")}\"" :
      var.decoy_scripts.token_type == "aws" ?
      "AWS_ACCESS_KEY_ID = \"AKIA${try(random_string.script_token[f].result, "")}\"\nAWS_SECRET_ACCESS_KEY = \"${try(random_password.script_secret[f].result, "")}\"" :
      "SERVICE_ACCOUNT_INFO = json.loads(r'''${try(base64decode(google_service_account_key.decoy[local.script_sa_key[f]].private_key), "{}")}''')"
    )
  }

  script_object_instances = var.decoy_scripts.enabled ? {
    for pair in setproduct(tolist(var.regions), local.scripts_selected) :
    "${pair[0]}::${pair[1]}" => { region = pair[0], script = pair[1] }
  } : {}
}

resource "random_id" "scripts_suffix" {
  count       = var.decoy_scripts.enabled ? 1 : 0
  byte_length = 2
  keepers = {
    name_prefix = var.decoy_scripts.name_prefix
    project_id  = var.project_id
  }
}

resource "random_string" "script_token" {
  for_each = var.decoy_scripts.enabled && contains(["gitlab", "aws"], var.decoy_scripts.token_type) ? toset(local.scripts_selected) : toset([])

  length  = var.decoy_scripts.token_type == "aws" ? 16 : 20
  upper   = true
  lower   = var.decoy_scripts.token_type != "aws"
  numeric = true
  special = false
}

resource "random_password" "script_secret" {
  for_each = var.decoy_scripts.enabled && var.decoy_scripts.token_type == "aws" ? toset(local.scripts_selected) : toset([])

  length  = 40
  special = false
}

resource "google_storage_bucket" "scripts" {
  for_each = var.decoy_scripts.enabled ? toset(var.regions) : toset([])

  project  = var.project_id
  name     = "${var.decoy_scripts.name_prefix}-${random_id.scripts_suffix[0].hex}-${each.key}"
  location = each.key

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  labels = local.common_labels
}

resource "google_storage_bucket_object" "script" {
  for_each = local.script_object_instances

  bucket = google_storage_bucket.scripts[each.value.region].name
  name   = local.script_paths[each.value.script]
  content = templatefile("${path.module}/templates/scripts/${each.value.script}", {
    credentials = local.script_credentials[each.value.script]
  })

  lifecycle {
    precondition {
      condition     = var.decoy_scripts.token_type != "gcp_sa_key" || (var.service_account.generate_key && var.service_account.count > 0)
      error_message = "decoy_scripts.token_type = gcp_sa_key requires service_account.generate_key = true and count > 0 (the script embeds the module's bait SA key)."
    }
  }
}
