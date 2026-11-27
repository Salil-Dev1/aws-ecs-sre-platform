resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "high_5xx_rate" {
  alarm_name          = "${var.project_name}-backend-high-5xx-rate"
  alarm_description   = "Backend target responses are returning an elevated number of 5xx errors."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.taskflow.arn_suffix
    TargetGroup  = aws_lb_target_group.backend.arn_suffix
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "high_p95_latency" {
  alarm_name          = "${var.project_name}-backend-high-p95-latency"
  alarm_description   = "Backend target p95 response time is above one second."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.taskflow.arn_suffix
    TargetGroup  = aws_lb_target_group.backend.arn_suffix
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name          = "${var.project_name}-backend-unhealthy-targets"
  alarm_description   = "At least one backend target is unhealthy."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.taskflow.arn_suffix
    TargetGroup  = aws_lb_target_group.backend.arn_suffix
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_dashboard" "taskflow" {
  dashboard_name = "${var.project_name}-operations"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title   = "Backend errors and p95 latency"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.taskflow.arn_suffix, "TargetGroup", aws_lb_target_group.backend.arn_suffix, { stat = "Sum", label = "Target 5xx" }],
            [".", "TargetResponseTime", "LoadBalancer", aws_lb.taskflow.arn_suffix, "TargetGroup", aws_lb_target_group.backend.arn_suffix, { stat = "p95", label = "Target p95 seconds", yAxis = "right" }],
          ]
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title   = "ECS service CPU and memory"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.taskflow.name, "ServiceName", aws_ecs_service.backend.name, { stat = "Average", label = "Backend CPU" }],
            [".", "MemoryUtilization", "ClusterName", aws_ecs_cluster.taskflow.name, "ServiceName", aws_ecs_service.backend.name, { stat = "Average", label = "Backend memory" }],
            [".", "CPUUtilization", "ClusterName", aws_ecs_cluster.taskflow.name, "ServiceName", aws_ecs_service.frontend.name, { stat = "Average", label = "Frontend CPU" }],
            [".", "MemoryUtilization", "ClusterName", aws_ecs_cluster.taskflow.name, "ServiceName", aws_ecs_service.frontend.name, { stat = "Average", label = "Frontend memory" }],
          ]
        }
      },
    ]
  })
}
