
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ==========================================
# AWS PROVIDER
# ==========================================

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ==========================================
# ECR REPOSITORIES
# ==========================================

resource "aws_ecr_repository" "app1" {
  name                 = "my-docker-app/app1"
  image_tag_mutability = "MUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository" "app2" {
  name                 = "my-docker-app/app2"
  image_tag_mutability = "MUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# ==========================================
# GITHUB ACTIONS ECR IAM POLICY
# ==========================================

data "aws_iam_policy_document" "ecr_access" {

  statement {
    sid    = "ECRAuthorization"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "PushPullImages"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]

    resources = [
      aws_ecr_repository.app1.arn,
      aws_ecr_repository.app2.arn
    ]
  }
}

resource "aws_iam_policy" "ecr_access" {
  name   = "my-docker-app-ecr-push-pull"
  policy = data.aws_iam_policy_document.ecr_access.json
}

# ==========================================
# GITHUB OIDC PROVIDER
# ==========================================

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]
}

# ==========================================
# GITHUB ACTIONS TRUST POLICY
# ==========================================

data "aws_iam_policy_document" "github_trust" {

  statement {
    sid     = "GitHubActionsTrust"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.github.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main"
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name = "my-docker-app-github-actions"

  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

resource "aws_iam_role_policy_attachment" "github_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_access.arn
}

# ==========================================
# DEFAULT VPC AND SUBNETS
# ==========================================

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ==========================================
# APPLICATION LOAD BALANCER SECURITY GROUP
# ==========================================

resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = "Allow inbound HTTP traffic to ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# ECS TASK SECURITY GROUP
# ==========================================

resource "aws_security_group" "ecs_sg" {
  name        = "ecs-security-group"
  description = "Allow traffic from ALB to ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Allow Flask traffic from ALB"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# APPLICATION LOAD BALANCER
# ==========================================

resource "aws_lb" "main" {
  name               = "app-load-balancer"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb_sg.id
  ]

  subnets = data.aws_subnets.default.ids

  enable_deletion_protection = false
}

# ==========================================
# ALB TARGET GROUP
# ==========================================

resource "aws_lb_target_group" "app" {
  name        = "ecs-target-app1"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
  }
  lifecycle {
    create_before_destroy = true
  }
}

# ==========================================
# TARGET GROUP FOR APP2
# ==========================================

resource "aws_lb_target_group" "app2" {
  name        = "ecs-target-app2"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
  }
}

# ==========================================
# ALB LISTENER
# ==========================================

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404 - Application not found"
      status_code  = "404"
    }
  }
}

# ==========================================
# ROUTING RULE FOR APP1
# ==========================================

resource "aws_lb_listener_rule" "app1" {
  listener_arn = aws_lb_listener.web.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    path_pattern {
      values = ["/app1", "/app1/*"]
    }
  }
}

# ==========================================
# ROUTING RULE FOR APP2
# ==========================================

resource "aws_lb_listener_rule" "app2" {
  listener_arn = aws_lb_listener.web.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app2.arn
  }

  condition {
    path_pattern {
      values = ["/app2", "/app2/*"]
    }
  }
}



# ==========================================
# ECS TASK DEFINITION - APP1
# ==========================================

resource "aws_ecs_task_definition" "app" {
  family                   = "my-web-app1"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "app1-container"
      image     = "${aws_ecr_repository.app1.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "app1"
        }
      }
    }
  ])

  depends_on = [
    aws_iam_role_policy_attachment.ecs_execution_role_attachment
  ]
}

# ==========================================
# ECS TASK DEFINITION - APP2
# ==========================================

resource "aws_ecs_task_definition" "app2" {
  family                   = "my-web-app2"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "app2-container"
      image     = "${aws_ecr_repository.app2.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "app2"
        }
      }
    }
  ])

  depends_on = [
    aws_iam_role_policy_attachment.ecs_execution_role_attachment
  ]
}



# ==========================================
# ECS SERVICE - APP1
# ==========================================

resource "aws_ecs_service" "app" {
  name            = "my-web-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn

  desired_count = 1
  launch_type   = "FARGATE"

  network_configuration {
    subnets = data.aws_subnets.default.ids

    security_groups = [
      aws_security_group.ecs_sg.id
    ]

    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app1-container"
    container_port   = 5000
  }

  depends_on = [
    aws_lb_listener_rule.app1,
    aws_iam_role_policy_attachment.ecs_execution_role_attachment
  ]
}

# ==========================================
# ECS SERVICE - APP2
# ==========================================

resource "aws_ecs_service" "app2" {
  name            = "my-web-app2-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app2.arn

  desired_count = 1
  launch_type   = "FARGATE"

  network_configuration {
    subnets = data.aws_subnets.default.ids

    security_groups = [
      aws_security_group.ecs_sg.id
    ]

    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app2.arn
    container_name   = "app2-container"
    container_port   = 5000
  }

  depends_on = [
    aws_lb_listener_rule.app2,
    aws_iam_role_policy_attachment.ecs_execution_role_attachment
  ]
}

# ==========================================
# CLOUDWATCH LOG GROUP
# ==========================================

resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/my-web-app"
  retention_in_days = 7
}

# ==========================================
# ECS CLUSTER
# ==========================================

resource "aws_ecs_cluster" "main" {
  name = "my-docker-app-cluster"
}

# ==========================================
# ECS TASK EXECUTION ROLE
# ==========================================

data "aws_iam_policy_document" "ecs_execution_role_policy" {

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = [
        "ecs-tasks.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "my-ecs-execution-role"

  assume_role_policy = data.aws_iam_policy_document.ecs_execution_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_attachment" {
  role = aws_iam_role.ecs_execution_role.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ==========================================
# ECS TASK DEFINITION
# ==========================================


# ==========================================
# ECS FARGATE SERVICE
# ==========================================



# ==========================================
# OUTPUTS
# ==========================================

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "ecr_app1_repository_url" {
  description = "ECR repository URL for app1"
  value       = aws_ecr_repository.app1.repository_url
}

output "ecr_app2_repository_url" {
  description = "ECR repository URL for app2"
  value       = aws_ecr_repository.app2.repository_url
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.main.dns_name
}

output "application_url" {
  description = "Application HTTP URL"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

# ==========================================
# APPLICATION URLS
# ==========================================

output "app1_url" {
  description = "URL for application 1"
  value       = "http://${aws_lb.main.dns_name}/app1"
}

output "app2_url" {
  description = "URL for application 2"
  value       = "http://${aws_lb.main.dns_name}/app2"
}

output "ecs_app1_service" {
  value = aws_ecs_service.app.name
}

output "ecs_app2_service" {
  value = aws_ecs_service.app2.name
}

output "app1_target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "app2_target_group_arn" {
  value = aws_lb_target_group.app2.arn
}
