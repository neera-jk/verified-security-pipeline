# ---------------------------------------------------------------
# SNS topic for pipeline alerts
# ---------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "team13-pipeline-alerts"

  tags = { Name = "team13-pipeline-alerts" }
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "shivaprasad.t@northeastern.edu"
}

# ---------------------------------------------------------------
# Alarms
# ---------------------------------------------------------------

# The scan script emits Team13/ScanSucceeded only when a run finishes
# cleanly. No datapoint therefore means a run was skipped or failed
# partway, so missing data is treated as breaching.
resource "aws_cloudwatch_metric_alarm" "scan_missed" {
  alarm_name          = "team13-scan-missed"
  alarm_description   = "No successful scan reported in the last two hours"
  namespace           = "Team13"
  metric_name         = "ScanSucceeded"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# A correlation failure means findings never get verified, so the
# pipeline is silently producing nothing.
resource "aws_cloudwatch_metric_alarm" "correlate_errors" {
  alarm_name          = "team13-correlate-errors"
  alarm_description   = "The correlation Lambda returned an error"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.correlate.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ---------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "team13-pipeline"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "Successful scans per hour"
          region  = "us-east-1"
          view    = "timeSeries"
          stat    = "Sum"
          period  = 3600
          metrics = [["Team13", "ScanSucceeded"]]
          yAxis   = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Correlation Lambda invocations and errors"
          region = "us-east-1"
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.correlate.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.correlate.function_name]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Correlation Lambda duration p99"
          region = "us-east-1"
          view   = "timeSeries"
          stat   = "p99"
          period = 300
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.correlate.function_name]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Scan index writes"
          region = "us-east-1"
          view   = "timeSeries"
          stat   = "Sum"
          period = 3600
          metrics = [
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.scan_index.name]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "log", x = 0, y = 12, width = 24, height = 6
        properties = {
          title  = "Recent correlation results"
          region = "us-east-1"
          query  = "SOURCE '/aws/lambda/team13-correlate' | fields @timestamp, @message | filter @message like /Confirmed/ | sort @timestamp desc | limit 20"
          view   = "table"
        }
      }
    ]
  })
}

output "dashboard_url" {
  value = "https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=team13-pipeline"
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
