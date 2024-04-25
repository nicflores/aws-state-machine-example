terraform {
  required_providers {
    aws = {
      version = ">= 5.46.0"
      source  = "hashicorp/aws"
    }
  }
}

terraform {
  backend "local" {}
}

variable "aws_region" {
  default = "us-east-1"
}

resource "aws_s3_bucket" "test_bucket" {
  bucket        = "nf-test-sf-bucket"
  force_destroy = true
}

resource "aws_iam_role" "lambda_iam" {
  name = "LambdaExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
}

data "aws_iam_policy_document" "lambda_iam_policy_doc" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
    effect    = "Allow"
  }
}

resource "aws_iam_policy" "lambda_iam_policy" {
  name   = "lambda_cloudwatch_iam_policy"
  policy = data.aws_iam_policy_document.lambda_iam_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "lambda_exec_policy_attachment" {
  role       = aws_iam_role.lambda_iam.name
  policy_arn = aws_iam_policy.lambda_iam_policy.arn
}


################## State Machine Permissions ##############

resource "aws_iam_policy" "lambda_sfn_policy" {
  name        = "LambdaStepFunctionsExecutionPolicy"
  description = "Allow lambda to start Step Functions executions"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "states:StartExecution",
      "Resource": "arn:aws:states:us-east-1:587747483980:stateMachine:FileProcessingStateMachine"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_sfn_policy_attachment" {
  role       = aws_iam_role.lambda_iam.name
  policy_arn = aws_iam_policy.lambda_sfn_policy.arn
}


################### Bucket Notification #################

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.test_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.initiator.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = ".txt"
  }
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.initiator.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.test_bucket.arn
}

################### Initial Lambda #####################

data "archive_file" "initial_lambda_zip" {
  type        = "zip"
  source_file = "initial_handler.py"
  output_path = "initial_handler.zip"
}

resource "aws_lambda_function" "initiator" {
  function_name    = "initialLambda"
  handler          = "initial_handler.lambda_handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_iam.arn
  filename         = data.archive_file.initial_lambda_zip.output_path
  source_code_hash = data.archive_file.initial_lambda_zip.output_base64sha256
}

############### Upload file Lambda ###############

data "archive_file" "upload_lambda_zip" {
  type        = "zip"
  source_file = "upload_handler.py"
  output_path = "upload_handler.zip"
}

resource "aws_lambda_function" "uploader" {
  function_name = "uploadFile"
  handler       = "upload_handler.lambda_handler"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_iam.arn
  filename      = data.archive_file.upload_lambda_zip.output_path
}

############## Download Lambda ###################

data "archive_file" "download_lambda_zip" {
  type        = "zip"
  source_file = "download_handler.py"
  output_path = "download_handler.zip"
}

resource "aws_lambda_function" "downloader" {
  function_name = "downloadFile"
  handler       = "download_handler.lambda_handler"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_iam.arn
  filename      = data.archive_file.download_lambda_zip.output_path
}


################# File Readiness Lambda ###################

data "archive_file" "readiness_lambda_zip" {
  type        = "zip"
  source_file = "readiness_handler.py"
  output_path = "readiness_handler.zip"
}

resource "aws_lambda_function" "readiness" {
  function_name = "readinessFile"
  handler       = "readiness_handler.py"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_iam.arn
  filename      = data.archive_file.readiness_lambda_zip.output_path
}

################ Error Notify Lambda ####################

data "archive_file" "notifier_lambda_zip" {
  type        = "zip"
  source_file = "error_handler.py"
  output_path = "error_handler.zip"
}

resource "aws_lambda_function" "notifier" {
  function_name = "errorNotification"
  handler       = "error_handler.py"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_iam.arn
  filename      = data.archive_file.notifier_lambda_zip.output_path
}


################ Step Function #####################

resource "aws_iam_role" "step_functions" {
  name = "StepFunctionsExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

# Step Functions state machine
resource "aws_sfn_state_machine" "file_processing_state_machine" {
  name     = "FileProcessingStateMachine"
  role_arn = aws_iam_role.step_functions.arn

  logging_configuration {
    level                  = "ALL"
    include_execution_data = true
    log_destination        = "${aws_cloudwatch_log_group.sfn_log_group.arn}:*"
  }

  definition = <<EOF
{
  "Comment": "A state machine to manage file processing",
  "StartAt": "UploadFile",
  "States": {
    "UploadFile": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.uploader.arn}",
      "Next": "InitialDelay",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "NotifyFailure"
        }
      ]
    },
    "InitialDelay": {
      "Type": "Wait",
      "SecondsPath": "$.initialCheckDelay",
      "Next": "CheckFileReadiness"
    },
    "CheckFileReadiness": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.readiness.arn}",
      "Next": "IsFileReady",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "NotifyFailure"
        }
      ]
    },
    "IsFileReady": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.fileReady",
          "BooleanEquals": true,
          "Next": "DownloadFile"
        },
        {
          "Variable": "$.retryCount",
          "NumericLessThan": 10,
          "Next": "Wait"
        }
      ],
      "Default": "NotifyFailure"
    },
    "DownloadFile": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.downloader.arn}",
      "End": true,
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "NotifyFailure"
        }
      ]
    },
    "Wait": {
      "Type": "Wait",
      "SecondsPath": "$.waitSeconds",
      "Next": "IncrementRetryCount"
    },
    "IncrementRetryCount": {
      "Type": "Pass",
      "InputPath": "$",
      "ResultPath": "$.retryCount",
      "Result": {
        "Fn.Add": ["$.retryCount", 1]
      },
      "Next": "CheckFileReadiness"
    },
    "NotifyFailure": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.notifier.arn}",
      "End": true
    }
  }
}
EOF
}

resource "aws_cloudwatch_log_group" "sfn_log_group" {
  name              = "/aws/states/FileProcessingStateMachine"
  retention_in_days = 14
}

# resource "aws_iam_policy" "sfn_logging_policy" {
#   name        = "SFNLoggingPolicy"
#   description = "Allow Step Functions to log to CloudWatch"
#   policy      = <<EOF
# {
#     "Version": "2012-10-17",
#     "Statement": [
#         {
#             "Effect": "Allow",
#             "Action": [
#                 "logs:CreateLogStream",
#                 "logs:CreateLogGroup",
#                 "logs:PutLogEvents"
#             ],
#             "Resource": "${aws_cloudwatch_log_group.sfn_log_group.arn}:*"
#         }
#     ]
# }
# EOF
# }

resource "aws_iam_role_policy_attachment" "sfn_logging_attachment" {
  role       = aws_iam_role.step_functions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonCloudWatchRUMFullAccess"
}
