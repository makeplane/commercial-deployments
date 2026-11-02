# External Secrets' identity: a Google service account bound to the controller's Kubernetes ServiceAccount through
# GKE Workload Identity, allowed to read each module secret (and the customer's certificate secrets) and nothing else.

locals {
  # Customer certificate secrets, "projects/<project>/secrets/<name>" (the root module checks the project).
  certificate_secret_names = toset([for s in var.certificate_secrets : regex("[^/]+$", s)])
}

resource "google_service_account" "external_secrets" {
  project      = var.project_id
  account_id   = "${var.name}-eso"
  display_name = "Plane ${var.name} External Secrets"
}

resource "google_secret_manager_secret_iam_member" "external_secrets" {
  for_each = var.secret_ids

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.external_secrets.member
}

resource "google_secret_manager_secret_iam_member" "external_secrets_certificates" {
  for_each = local.certificate_secret_names

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.external_secrets.member
}

# The <project>.svc.id.goog identity pool exists once the cluster does.
resource "google_service_account_iam_member" "external_secrets_workload_identity" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${local.external_secrets_namespace}/${local.external_secrets_sa}]"

  depends_on = [terraform_data.cluster_ready]
}
