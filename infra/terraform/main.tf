data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_route53_zone" "this" {
  count = var.manage_hosted_zone ? 0 : 1
  name  = var.domain_name
}

locals {
  api_base_url  = "https://${var.api_domain}"
  web_base_url  = var.web_base_url != "" ? var.web_base_url : "https://${var.web_domain}"
  cors_origins  = var.cors_origins != "" ? var.cors_origins : "https://${var.web_domain}"
  api_image     = "${aws_ecr_repository.api.repository_url}:${var.api_image_tag}"
  web_image     = "${aws_ecr_repository.web.repository_url}:${var.web_image_tag}"
  gemini_secret_arn  = try(aws_secretsmanager_secret.gemini[0].arn, null)
  cookies_secret_arn = try(aws_secretsmanager_secret.ytdlp_cookies[0].arn, null)
  proxy_secret_arn   = try(aws_secretsmanager_secret.ytdlp_proxy[0].arn, null)
  secret_arns        = compact([local.gemini_secret_arn, local.cookies_secret_arn, local.proxy_secret_arn])
  hosted_zone_id     = var.manage_hosted_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.this[0].zone_id
  hosted_zone_name_servers = var.manage_hosted_zone ? aws_route53_zone.this[0].name_servers : data.aws_route53_zone.this[0].name_servers
  api_env = concat(
    [
      { name = "APP_ENV", value = var.env },
      { name = "CORS_ORIGINS", value = local.cors_origins },
      { name = "WEB_BASE_URL", value = local.web_base_url }
    ],
    var.gemini_endpoint != "" ? [{ name = "GEMINI_ENDPOINT", value = var.gemini_endpoint }] : [],
    var.ytdlp_args != "" ? [{ name = "YTDLP_ARGS", value = var.ytdlp_args }] : []
  )
  api_secrets = concat(
    local.gemini_secret_arn != null ? [{ name = "GEMINI_API_KEY", valueFrom = local.gemini_secret_arn }] : [],
    local.cookies_secret_arn != null ? [{ name = "YTDLP_COOKIES", valueFrom = local.cookies_secret_arn }] : [],
    local.proxy_secret_arn != null ? [{ name = "YTDLP_PROXY", valueFrom = local.proxy_secret_arn }] : []
  )
}

resource "aws_security_group" "alb" {
  name        = "threadbrief-${var.env}-alb"
  description = "ALB ingress"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs" {
  name        = "threadbrief-${var.env}-ecs"
  description = "ECS service ingress from ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecr_repository" "api" {
  name                 = "threadbrief-${var.env}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "web" {
  name                 = "threadbrief-${var.env}-web"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/threadbrief/${var.env}/api"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/threadbrief/${var.env}/web"
  retention_in_days = 14
}

resource "aws_ecs_cluster" "this" {
  name = "threadbrief-${var.env}"
}

resource "aws_iam_role" "task_execution" {
  name = "threadbrief-${var.env}-task-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "ecs-tasks.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "secrets_read" {
  count = (var.gemini_api_key != "" || var.ytdlp_cookies != "" || var.ytdlp_proxy != "") ? 1 : 0
  name  = "threadbrief-${var.env}-secrets-read"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = local.secret_arns
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_secrets" {
  count      = (var.gemini_api_key != "" || var.ytdlp_cookies != "" || var.ytdlp_proxy != "") ? 1 : 0
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.secrets_read[0].arn
}

resource "aws_iam_role" "task" {
  name = "threadbrief-${var.env}-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "ecs-tasks.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_secretsmanager_secret" "gemini" {
  # If a secret is scheduled for deletion, restore it before apply (deploy handles this).
  count = var.gemini_api_key != "" ? 1 : 0
  name  = "threadbrief/${var.env}/gemini_api_key"
}

resource "aws_secretsmanager_secret_version" "gemini" {
  count         = var.gemini_api_key != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.gemini[0].id
  secret_string = var.gemini_api_key
}

resource "aws_secretsmanager_secret" "ytdlp_cookies" {
  # If a secret is scheduled for deletion, restore it before apply (deploy handles this).
  count = var.ytdlp_cookies != "" ? 1 : 0
  name  = "threadbrief/${var.env}/ytdlp_cookies"
}

resource "aws_secretsmanager_secret_version" "ytdlp_cookies" {
  count         = var.ytdlp_cookies != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.ytdlp_cookies[0].id
  secret_string = var.ytdlp_cookies
}

resource "aws_secretsmanager_secret" "ytdlp_proxy" {
  # If a secret is scheduled for deletion, restore it before apply (deploy handles this).
  count = var.ytdlp_proxy != "" ? 1 : 0
  name  = "threadbrief/${var.env}/ytdlp_proxy"
}

resource "aws_secretsmanager_secret_version" "ytdlp_proxy" {
  count         = var.ytdlp_proxy != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.ytdlp_proxy[0].id
  secret_string = var.ytdlp_proxy
}

resource "aws_iam_service_linked_role" "ecs" {
  aws_service_name = "ecs.amazonaws.com"
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "threadbrief-${var.env}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = jsonencode([
    {
      name      = "api"
      image     = local.api_image
      essential = true
      portMappings = [
        { containerPort = 8080, hostPort = 8080, protocol = "tcp" }
      ]
      environment = local.api_env
      secrets     = local.api_secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "web" {
  family                   = "threadbrief-${var.env}-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = jsonencode([
    {
      name      = "web"
      image     = local.web_image
      essential = true
      portMappings = [
        { containerPort = 3000, hostPort = 3000, protocol = "tcp" }
      ]
      environment = [
        { name = "NEXT_PUBLIC_API_BASE_URL", value = local.api_base_url }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.web.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "web"
        }
      }
    }
  ])
}

resource "aws_lb" "this" {
  name               = "threadbrief-${var.env}"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids
  idle_timeout       = 300
}

resource "aws_lb_target_group" "api" {
  name        = "threadbrief-${var.env}-api"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"
  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 20
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "web" {
  name        = "threadbrief-${var.env}-web"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"
  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 20
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_acm_certificate" "this" {
  domain_name               = var.web_domain
  subject_alternative_names = [var.api_domain]
  validation_method         = "DNS"
}

resource "aws_route53_zone" "this" {
  count = var.manage_hosted_zone ? 1 : 0
  name = var.domain_name
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }
  zone_id = local.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
  condition {
    host_header {
      values = [var.api_domain]
    }
  }
}

resource "aws_lb_listener_rule" "web" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
  condition {
    host_header {
      values = [var.web_domain]
    }
  }
}

resource "aws_ecs_service" "api" {
  name            = "threadbrief-${var.env}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8080
  }
  depends_on = [aws_lb_listener.https, aws_iam_service_linked_role.ecs]
}

resource "aws_ecs_service" "web" {
  name            = "threadbrief-${var.env}-web"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 3000
  }
  depends_on = [aws_lb_listener.https, aws_iam_service_linked_role.ecs]
}

resource "aws_route53_record" "web" {
  zone_id = local.hosted_zone_id
  name    = var.web_domain
  type    = "A"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api" {
  zone_id = local.hosted_zone_id
  name    = var.api_domain
  type    = "A"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}
