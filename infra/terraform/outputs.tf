output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "ALB DNS name."
}

output "route53_name_servers" {
  value       = local.hosted_zone_name_servers
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

output "web_s3_bucket" {
  value       = aws_s3_bucket.web.bucket
  description = "S3 bucket for the static web export (target of `aws s3 sync`)."
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.web.id
  description = "CloudFront distribution id (for cache invalidations)."
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.web.domain_name
  description = "CloudFront's own domain name (works over HTTPS before DNS cutover)."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.app.name
  description = "DynamoDB table backing briefs + rate limits."
}

output "lambda_function_url" {
  value       = aws_lambda_function_url.api.function_url
  description = "API Lambda Function URL (this is the real API base URL; no custom domain)."
}

output "lambda_function_name" {
  value       = aws_lambda_function.api.function_name
  description = "API Lambda function name."
}
