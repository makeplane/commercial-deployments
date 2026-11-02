output "plane_url" {
  description = "URL Plane is served on."
  value       = "https://${var.domain}"
}

output "deployment_mode" {
  description = "Deployment mode in use."
  value       = var.deployment_mode
}

output "load_balancer_ip" {
  description = "Path A: the reserved static IP of Traefik's load balancer (null in path B). Point domain here with an A record. Internal (an IP in the module's subnet) when ingress.scheme = \"internal\"."
  value       = module.edge.web_ip
}

output "email_load_balancer_ip" {
  description = "Reserved static IP of the email load balancer (null without email.load_balancer). email.smtp_domain's A record points here, and its MX record names smtp_domain."
  value       = module.edge.email_ip
}

output "dns_records" {
  description = "The DNS records to create (the module creates none). web: path A only; in path B, point domain at your own ingress load balancer. An MX record can't point at an IP, so the email service gets an A record (email_host) and an MX record naming it (email_mx)."
  value = {
    web = module.edge.web_ip == null ? null : {
      name  = var.domain
      type  = "A (DNS-only, no proxy)"
      value = module.edge.web_ip
    }
    email_host = module.edge.email_ip == null ? null : {
      name  = local.email.smtp_domain
      type  = "A"
      value = module.edge.email_ip
    }
    email_mx = module.edge.email_ip == null ? null : {
      name  = local.email.smtp_domain
      type  = "MX"
      value = "10 ${local.email.smtp_domain}"
    }
  }
}

output "network_name" {
  description = "VPC network name."
  value       = module.network.network_name
}

output "subnet_name" {
  description = "Subnet the GKE nodes run in."
  value       = module.network.subnet_name
}

output "cluster_name" {
  description = "GKE cluster name."
  value       = module.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "GKE API endpoint (https URL of the public endpoint)."
  value       = module.cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "GKE cluster CA (base64)."
  value       = module.cluster.cluster_certificate_authority_data
}

output "configure_kubectl" {
  description = "Command to point kubectl at the cluster (needs gcloud and gke-gcloud-auth-plugin)."
  value       = "gcloud container clusters get-credentials ${module.cluster.cluster_name} --region ${var.region} --project ${var.project_id}"
}

output "cloudsql_instance_name" {
  description = "Cloud SQL instance name."
  value       = module.data.postgres_instance_name
}

output "cloudsql_private_ip" {
  description = "Cloud SQL private IP."
  value       = module.data.postgres_host
}

output "redis_endpoint" {
  description = "Memorystore for Redis endpoint (host:port; port 6378 with TLS, 6379 without)."
  value       = "${module.data.redis_host}:${module.data.redis_port}"
}

output "rabbitmq_endpoint" {
  description = "In-cluster RabbitMQ (AMQP) host."
  value       = module.plane.rabbitmq_host
}

output "gcs_bucket_name" {
  description = "Uploads bucket."
  value       = module.data.bucket_name
}

output "secret_ids" {
  description = "Secret Manager secrets the deployment uses (IDs only, never values)."
  value       = module.data.secret_ids
}

output "plane_service_account_email" {
  description = "Google service account Plane's pods use through GKE Workload Identity."
  value       = module.plane.service_account_email
}

output "plane_helm_values" {
  description = "The plane-enterprise chart values the module generates from the infrastructure (YAML): endpoints, bucket, project, domain, load balancer and Secret names; no secret values. Excludes plane_values. For support, debugging and reading what was installed."
  value       = module.plane.helm_values
}
