# Reserved by Terraform, so the IPs survive a Service re-creation. The module creates no DNS records.

resource "google_compute_address" "web" {
  count = var.install_traefik ? 1 : 0

  project      = var.project_id
  name         = "${var.name}-web"
  region       = var.region
  address_type = var.web_scheme == "internal" ? "INTERNAL" : "EXTERNAL"
  # An internal load balancer takes its IP from the nodes' subnet.
  subnetwork   = var.web_scheme == "internal" ? var.subnet_id : null
  network_tier = var.web_scheme == "internal" ? null : "PREMIUM"
  labels       = var.labels
}

resource "google_compute_address" "email" {
  count = var.email_load_balancer ? 1 : 0

  project      = var.project_id
  name         = "${var.name}-email"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
  labels       = var.labels
}

# GKE removes the Services' forwarding rules asynchronously and an address in use can't be released.
resource "time_sleep" "lb_cleanup" {
  destroy_duration = "90s"

  depends_on = [google_compute_address.web, google_compute_address.email]
}
