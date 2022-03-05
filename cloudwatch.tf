#----------------
# CloudWatchLog
#----------------

resource "aws_cloudwatch_log_group" "ecs_api" {
  name              = "/ecs/api"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "ecs_event" {
  name              = "/ecs/event"
  retention_in_days = 30
}

#----------------
# CloudWatchEvent
#----------------

data "aws_iam_policy" "ecs_events_role_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceEventsRole"
}

module "ecs_events_role" {
  source     = "./iam_role"
  name       = "ecs-events"
  identifier = "events.amazonaws.com"
  policy     = data.aws_iam_policy.ecs_events_role_policy.policy
}

resource "aws_cloudwatch_event_rule" "batch" {
  name                = "batch"
  description         = "Aggregate ranking data from RDS"
  schedule_expression = "rate(3 hours)"
}

# resource "aws_cloudwatch_event_target" "batch" {
#   target_id = "batch"
#   rule      = aws_cloudwatch_event_rule.batch.name
#   role_arn  = module.ecs_events_role.iam_role_arn
#   arn       = aws_ecs_cluster.api.arn

#   ecs_target {
#     launch_type         = "FARGATE"
#     task_count          = 1
#     platform_version    = "1.4.0"
#     task_definition_arn = aws_ecs_task_definition.batch.arn

#     network_configuration {
#       assign_public_ip = "false"
#       subnets          = [aws_subnet.private_0.id]
#     }
#   }
# }
