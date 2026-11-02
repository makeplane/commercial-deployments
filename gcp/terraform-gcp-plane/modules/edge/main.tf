# Reserved static IPs for the passthrough network load balancers GKE creates for Traefik's Service (path A) and the
# email Service. Reserved by Terraform, so they survive a Service re-creation and give stable A records. The module
# creates no DNS records: the customer points domain (and smtp_domain) at these IPs.

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

# On destroy, the Services that use these IPs are deleted first (Traefik in the addons module, email in the plane
# module), and GKE removes their forwarding rules asynchronously. An address still in use can't be released, so
# wait before deleting the addresses.
resource "time_sleep" "lb_cleanup" {
  destroy_duration = "90s"

  depends_on = [google_compute_address.web, google_compute_address.email]
}
