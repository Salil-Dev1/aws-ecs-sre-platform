resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.project_name}/backend"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${var.project_name}/frontend"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_ecs_cluster" "taskflow" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project_name}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "${var.project_name}-backend"
    image     = "${aws_ecr_repository.backend.repository_url}:latest"
    essential = true
    cpu       = 256
    memory    = 512
    portMappings = [{
      containerPort = 8000
      hostPort      = 8000
      protocol      = "tcp"
    }]
    secrets = [{
      name      = "MONGO_URI"
      valueFrom = aws_ssm_parameter.mongo_uri.arn
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.backend.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "backend"
      }
    }
  }])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.project_name}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "${var.project_name}-frontend"
    image     = "${aws_ecr_repository.frontend.repository_url}:latest"
    essential = true
    cpu       = 256
    memory    = 512
    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.frontend.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "frontend"
      }
    }
  }])

  tags = local.common_tags
}

resource "aws_ecs_service" "backend" {
  name                               = "${var.project_name}-backend"
  cluster                            = aws_ecs_cluster.taskflow.id
  task_definition                    = aws_ecs_task_definition.backend.arn
  desired_count                      = 2
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.backend.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "${var.project_name}-backend"
    container_port   = 8000
  }

  depends_on = [
    aws_lb_listener_rule.api,
    aws_lb_listener_rule.health,
    aws_lb_listener_rule.metrics,
    aws_iam_role_policy_attachment.ecs_execution_managed,
    aws_iam_role_policy.ecs_execution_ssm,
  ]

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = local.common_tags
}

resource "aws_ecs_service" "frontend" {
  name                               = "${var.project_name}-frontend"
  cluster                            = aws_ecs_cluster.taskflow.id
  task_definition                    = aws_ecs_task_definition.frontend.arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.frontend.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "${var.project_name}-frontend"
    container_port   = 8080
  }

  depends_on = [
    aws_lb_listener_rule.frontend,
    aws_iam_role_policy_attachment.ecs_execution_managed,
  ]

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = local.common_tags
}
