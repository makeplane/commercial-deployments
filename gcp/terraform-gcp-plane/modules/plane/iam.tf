# No Secret Manager access: External Secrets reads the secrets, Plane only reads Kubernetes Secrets.

resource "google_service_account" "plane" {
  project      = var.project_id
  account_id   = "${var.name}-plane"
  display_name = "Plane ${var.name}"
  description  = "Plane's pods (GKE Workload Identity): the uploads bucket only."
}

# legacyBucketReader adds storage.buckets.get, which silo uses to check the bucket at startup.
resource "google_storage_bucket_iam_member" "plane" {
  for_each = toset(["roles/storage.objectAdmin", "roles/storage.legacyBucketReader"])

  bucket = var.data.bucket_name
  role   = each.value
  member = google_service_account.plane.member
}

# Keyless signed URLs: Plane signs through the IAM signBlob API, which needs TokenCreator on itself.
resource "google_service_account_iam_member" "plane_token_creator" {
  service_account_id = google_service_account.plane.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = google_service_account.plane.member
}

# The <project>.svc.id.goog identity pool exists once the cluster does (addons_ready comes after it).
resource "google_service_account_iam_member" "plane_workload_identity" {
  service_account_id = google_service_account.plane.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${local.namespace}/${local.service_account}]"

  depends_on = [terraform_data.addons_ready]
}
