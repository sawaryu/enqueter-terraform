#----------------
# ECR
#----------------
resource "aws_ecr_repository" "api" {
  name = "api"
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = <<EOF
  {
    "rules": [
      {
        "rulePriority": 1,
        "description": "keep last 30 release tagged images",
        "selection": {
          "tagStatus": "tagged",
          "tagPrefixList": ["release"],
          "countType": "imageCountMoreThan",
          "countNumber": 30
        },
        "action": {
          "type": "expire"
        }
      }
    ]
  }
EOF
}

resource "aws_ecr_repository" "nginx" {
  name = "nginx"
}

resource "aws_ecr_lifecycle_policy" "nginx" {
  repository = aws_ecr_repository.nginx.name

  policy = <<EOF
  {
    "rules": [
      {
        "rulePriority": 1,
        "description": "keep last 30 release tagged images",
        "selection": {
          "tagStatus": "tagged",
          "tagPrefixList": ["release"],
          "countType": "imageCountMoreThan",
          "countNumber": 30
        },
        "action": {
          "type": "expire"
        }
      }
    ]
  }
EOF
}

#----------------
# ECS Fargate (api)
#----------------
resource "aws_ecs_cluster" "api" {
  name = "api"
}

resource "aws_ecs_service" "api" {
  name                              = "api"                           # Assign the name of cluster
  cluster                           = aws_ecs_cluster.api.arn         # Assign the arn of cluster
  task_definition                   = aws_ecs_task_definition.api.arn # Assign the arn of task definition
  desired_count                     = 2                               # If you want to stop service temporaly, set "0"
  launch_type                       = "FARGATE"
  platform_version                  = "1.4.0" # Should assign latest version. (* Don't use 'latest')
  health_check_grace_period_seconds = 60      # Recommended to set little longer time.

  network_configuration {
    assign_public_ip = false # On the private ip
    security_groups  = [module.nginx_sg.security_group_id]

    subnets = [
      aws_subnet.private_0.id,
      aws_subnet.private_1.id,
    ]
  }

  # Associate with ALB on the port "80"
  load_balancer {
    target_group_arn = aws_lb_target_group.nginx.arn
    container_name   = "nginx" # container_name from Task Definition
    container_port   = 80
  }

  lifecycle {
    ignore_changes = [
      task_definition
    ]
  }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "api" # Name of Task definiton (will increment)
  cpu                      = "256" # Attention to combinations of the cpu*memory
  memory                   = "512"
  network_mode             = "awsvpc" # In case of "Fargate", must be "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = file("./task_definitions/api_task.json")

  # Socket communication between containers
  volume {
    name = "socket"
  }

  # Enable Docker container to output logs to CloudWatchlogs
  execution_role_arn = module.ecs_task_execution_role.iam_role_arn
}

module "nginx_sg" {
  source      = "./security_group"
  name        = "nginx-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = [aws_vpc.example.cidr_block]
}

#----------------
# ECS Fargate (Batch *executed by CloudWatchEvent)
#----------------

resource "aws_ecs_task_definition" "batch" {
  family                   = "batch"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = file("./task_definitions/batch_task.json")
  execution_role_arn       = module.ecs_task_execution_role.iam_role_arn
}

#----------------
# ECS Fargate (another tasks)
#----------------

resource "aws_ecs_task_definition" "seed" {
  family                   = "seed"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = file("./task_definitions/seed_task.json")
  execution_role_arn       = module.ecs_task_execution_role.iam_role_arn
}

resource "aws_ecs_task_definition" "drop" {
  family                   = "drop"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = file("./task_definitions/drop_task.json")
  execution_role_arn       = module.ecs_task_execution_role.iam_role_arn
}

resource "aws_ecs_task_definition" "migrate" {
  family                   = "migrate"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = file("./task_definitions/migrate_task.json")
  execution_role_arn       = module.ecs_task_execution_role.iam_role_arn
}

#----------------
# Role for tasks
#----------------
module "ecs_task_execution_role" {
  source     = "./iam_role"
  name       = "ecs-task-execution"
  identifier = "ecs-tasks.amazonaws.com"
  policy     = data.aws_iam_policy_document.ecs_task_execution.json
}
data "aws_iam_policy" "ecs_task_execution_role_policy" {
  # This policy enable tasks to control CloudWatch log, ECR and so on.
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_execution" {
  source_json = data.aws_iam_policy.ecs_task_execution_role_policy.policy

  statement {
    effect = "Allow"
    # enable access to SSM and KMS
    actions   = ["ssm:GetParameters", "kms:Decrypt"]
    resources = ["*"]
  }
}
