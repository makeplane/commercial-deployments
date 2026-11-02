# Browsers use signed URLs directly, hence CORS. GCS refuses plain HTTP, so no TLS-only policy is needed.

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "uploads" {
  # checkov:skip=CKV_GCP_62:Access logging needs a separate log bucket; customer choice.
  project       = var.project_id
  name          = "${var.name}-uploads-${random_id.bucket_suffix.hex}"
  location      = upper(var.region)
  force_destroy = var.bucket_force_destroy

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 30
      with_state                 = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  cors {
    origin          = ["https://${var.domain}"]
    method          = ["GET", "HEAD", "PUT", "POST"]
    response_header = ["Content-Type", "Content-Disposition", "ETag", "x-goog-resumable"]
    max_age_seconds = 3600
  }

  labels = var.labels
}
