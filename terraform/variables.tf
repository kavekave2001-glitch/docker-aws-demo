variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "github_owner" {
  type        = string
  description = "GitHub username or organization"
  default     = "kavekave2001-glitch"
}

variable "github_repo" {
  type    = string
  default = "docker-aws-demo"
}