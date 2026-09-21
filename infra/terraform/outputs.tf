output "route53_name_servers" {
  value       = local.hosted_zone_name_servers
  description = "Route53 name servers to set in GoDaddy."
}

output "api_ecr_url" {
  value       = aws_ecr_repository.api.repository_url
  description = "API ECR repository URL."
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
  description = "CloudFront's own domain name."
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
