# API compute: Lambda (container image) behind a Function URL. Not API
# Gateway — both REST and HTTP APIs hard-cap integration timeouts at ~30s,
# and brief generation (transcript fetch + Gemini call) can legitimately take
# several minutes for long videos. Function URLs inherit Lambda's own timeout
# (up to 900s) instead. Trade-off: no custom domain for the API; the web app
# points NEXT_PUBLIC_API_BASE_URL directly at the Function URL.

resource "aws_dynamodb_table" "app" {
  name         = "threadbrief-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_iam_role" "lambda_api" {
  name = "threadbrief-${var.env}-lambda-api"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "lambda.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_api_basic_execution" {
  role       = aws_iam_role.lambda_api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_api_dynamodb" {
  name = "threadbrief-${var.env}-lambda-api-dynamodb"
  role = aws_iam_role.lambda_api.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"],
        Resource = aws_dynamodb_table.app.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda_api" {
  name              = "/aws/lambda/threadbrief-${var.env}-api"
  retention_in_days = 14
}

resource "aws_lambda_function" "api" {
  function_name = "threadbrief-${var.env}-api"
  role          = aws_iam_role.lambda_api.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.api.repository_url}:${var.api_lambda_image_tag}"
  timeout       = 900
  memory_size   = 1024

  environment {
    variables = merge(
      {
        APP_ENV           = var.env
        CORS_ORIGINS      = local.cors_origins
        WEB_BASE_URL      = local.web_base_url
        MAX_VIDEO_MINUTES = tostring(var.max_video_minutes)
        STORAGE_BACKEND   = "dynamodb"
        DYNAMODB_TABLE    = aws_dynamodb_table.app.name
      },
      var.gemini_api_key != "" ? { GEMINI_API_KEY = var.gemini_api_key } : {},
      var.gemini_endpoint != "" ? { GEMINI_ENDPOINT = var.gemini_endpoint } : {},
      var.ytdlp_args != "" ? { YTDLP_ARGS = var.ytdlp_args } : {},
      var.ytdlp_cookies != "" ? { YTDLP_COOKIES = var.ytdlp_cookies } : {},
      var.ytdlp_proxy != "" ? { YTDLP_PROXY = var.ytdlp_proxy } : {},
    )
  }

  depends_on = [aws_cloudwatch_log_group.lambda_api]
}

resource "aws_lambda_function_url" "api" {
  function_name      = aws_lambda_function.api.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "api_function_url_public" {
  statement_id           = "AllowPublicInvokeFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.api.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
