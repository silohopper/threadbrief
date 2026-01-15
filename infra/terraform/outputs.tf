output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "ALB DNS name."
}

output "route53_name_servers" {
  value       = aws_route53_zone.this.name_servers
  description = "Route53 name servers to set in GoDaddy."
}

output "acm_validation_records" {
  value = [
    for dvo in aws_acm_certificate.this.domain_validation_options : {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  ]
  description = "ACM DNS validation records (for GoDaddy DNS)."
}

output "api_ecr_url" {
  value       = aws_ecr_repository.api.repository_url
  description = "API ECR repository URL."
}

output "web_ecr_url" {
  value       = aws_ecr_repository.web.repository_url
  description = "Web ECR repository URL."
}

output "ecs_cluster_name" {
  value       = aws_ecs_cluster.this.name
  description = "ECS cluster name."
}

output "api_service_name" {
  value       = aws_ecs_service.api.name
  description = "ECS API service name."
}

output "web_service_name" {
  value       = aws_ecs_service.web.name
  description = "ECS web service name."
}

output "api_domain" {
  value       = var.api_domain
  description = "API domain."
}

output "web_domain" {
  value       = var.web_domain
  description = "Web domain."
}
