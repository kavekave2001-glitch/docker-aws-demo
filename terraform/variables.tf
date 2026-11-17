variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "github_owner" {
  type        = string
  description = "GitHub username or organization"
}

variable "github_repo" {
  type    = string
  default = "my-docker-app"
}
