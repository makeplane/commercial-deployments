# Plane's pods reach GCS through GKE Workload Identity: no keys anywhere. The chart's ServiceAccount is
# "<release>-srv-account"; Workload Identity binds it to this Google service account by name. No Secret Manager
# access: External Secrets reads the secrets, Plane only reads Kubernetes Secrets.

resource "google_service_account" "plane" {
  project      = var.project_id
  account_id   = "${var.name}-plane"
  display_name = "Plane ${var.name}"
  description  = "Plane's pods (GKE Workload Identity): the uploads bucket only."
}

# objectAdmin covers what the api and silo do (get, put, delete and copy objects, list the bucket). legacyBucketReader
# adds storage.buckets.get, which silo uses to verify the bucket at startup. Both on this bucket only.
resource "google_storage_bucket_iam_member" "plane" {
  for_each = toset(["roles/storage.objectAdmin", "roles/storage.legacyBucketReader"])

  bucket = var.data.bucket_name
  role   = each.value
  member = google_service_account.plane.member
}

# Signed URLs without a key: Plane signs through the IAM signBlob API as this service account, which needs
# TokenCreator on itself.
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
