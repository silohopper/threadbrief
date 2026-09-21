data "aws_route53_zone" "this" {
  count        = var.manage_hosted_zone ? 0 : 1
  zone_id      = var.route53_zone_id != "" ? var.route53_zone_id : null
  name         = var.route53_zone_id == "" ? var.domain_name : null
  private_zone = false
}

locals {
  web_base_url             = var.web_base_url != "" ? var.web_base_url : "https://${var.web_domain}"
  cors_origins             = var.cors_origins != "" ? var.cors_origins : "https://${var.web_domain}"
  hosted_zone_id           = var.manage_hosted_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.this[0].zone_id
  hosted_zone_name_servers = var.manage_hosted_zone ? aws_route53_zone.this[0].name_servers : data.aws_route53_zone.this[0].name_servers
}

resource "aws_ecr_repository" "api" {
  name                 = "threadbrief-${var.env}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_route53_zone" "this" {
  count = var.manage_hosted_zone ? 1 : 0
  name  = var.domain_name
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "web" {
  zone_id = local.hosted_zone_id
  name    = var.web_domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.web.domain_name
    zone_id                = aws_cloudfront_distribution.web.hosted_zone_id
    evaluate_target_health = false
  }
}

# No aws_route53_record.api: Lambda Function URLs don't support custom
# domains, so the API is reached directly via its Function URL
# (see outputs.tf: lambda_function_url). api_domain / api.<env> DNS is
# intentionally left unused.
