variable "env" {
  type        = string
  description = "Environment name (stage/prod)."
}

variable "aws_region" {
  type        = string
  description = "AWS region."
  default     = "ap-southeast-2"
}

variable "domain_name" {
  type        = string
  description = "Base domain name (e.g. threadbrief.com)."
}

variable "web_domain" {
  type        = string
  description = "Web host name (e.g. staging.threadbrief.com)."
}

variable "api_domain" {
  type        = string
  description = "API host name (e.g. api.staging.threadbrief.com)."
}

variable "api_image_tag" {
  type        = string
  description = "API image tag to deploy."
  default     = "latest"
}

variable "web_image_tag" {
  type        = string
  description = "Web image tag to deploy."
  default     = "latest"
}

variable "gemini_api_key" {
  type        = string
  description = "Gemini API key (stored in Secrets Manager)."
  sensitive   = true
  default     = ""
}

variable "gemini_endpoint" {
  type        = string
  description = "Optional Gemini endpoint override."
  default     = ""
}

variable "ytdlp_args" {
  type        = string
  description = "Optional yt-dlp args (e.g. --js-runtimes node)."
  default     = "--js-runtimes node"
}

variable "ytdlp_cookies" {
  type        = string
  description = "Optional yt-dlp cookies.txt contents."
  sensitive   = true
  default     = ""
}

variable "ytdlp_proxy" {
  type        = string
  description = "Optional yt-dlp proxy URL (e.g. http://user:pass@host:port)."
  sensitive   = true
  default     = ""
}

variable "cors_origins" {
  type        = string
  description = "CORS origins for the API."
  default     = ""
}

variable "web_base_url" {
  type        = string
  description = "Base URL for share links."
  default     = ""
}

variable "manage_hosted_zone" {
  type        = bool
  description = "Whether this env owns/creates the Route53 hosted zone."
  default     = false
}
