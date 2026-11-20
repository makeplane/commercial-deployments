# External Secrets reads the module's secrets and the customer's secrets (certificates, AI provider keys), nothing else.

locals {
  # The root module checks the project, so the short name is enough.
  customer_secret_names = toset([for s in var.customer_secrets : regex("[^/]+$", s)])
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

resource "google_secret_manager_secret_iam_member" "external_secrets_customer" {
  for_each = local.customer_secret_names

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
