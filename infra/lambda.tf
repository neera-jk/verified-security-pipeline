data "aws_caller_identity" "current" {}

data "archive_file" "correlate" {
  type        = "zip"
  source_file = "${path.module}/../lambda/correlate/index.mjs"
  output_path = "${path.module}/correlate.zip"
}

resource "aws_lambda_function" "correlate" {
  function_name    = "team13-correlate"
  filename         = data.archive_file.correlate.output_path
  source_code_hash = data.archive_file.correlate.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  role             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.scan_index.name
      ALERT_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }

  tags = { Name = "team13-correlate" }
}

resource "aws_cloudwatch_log_group" "correlate" {
  name              = "/aws/lambda/team13-correlate"
  retention_in_days = 7
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.correlate.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::team13-vsp-reports-33c3b3e1"
}

resource "aws_s3_bucket_notification" "reports" {
  bucket = "team13-vsp-reports-33c3b3e1"

  lambda_function {
    lambda_function_arn = aws_lambda_function.correlate.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "sast/"
    filter_suffix       = ".json"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.correlate.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "pentest/"
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

output "correlate_function_name" {
  value = aws_lambda_function.correlate.function_name
}
