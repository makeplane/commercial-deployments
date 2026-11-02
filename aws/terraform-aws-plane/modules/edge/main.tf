# The NLB in front of the module's Traefik (path A), looked up by its fixed name once Traefik is
# installed. The module creates no DNS records: the customer points domain at this NLB's hostname.
# Its IPs are assigned by AWS and can change, so DNS must use the hostname (CNAME or alias).

# Read the NLB only after Traefik's Service has it (helm waits for the LoadBalancer address).
resource "terraform_data" "addons_ready" {
  input = var.addons_ready
}

data "aws_lb" "traefik" {
  count = var.install_traefik ? 1 : 0

  name = var.load_balancer_name

  depends_on = [terraform_data.addons_ready]
}
