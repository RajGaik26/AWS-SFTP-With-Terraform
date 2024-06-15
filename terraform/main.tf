# AWS Provider Configuration
provider "aws" {
  region = "eu-west-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# S3 Buckets for Data and Logs
resource "aws_s3_bucket" "data_lake" {
  bucket = "agency-data-lake"
  tags = {
    Name        = "AgencyDataLake"
    Environment = "Production"
  }
}

resource "aws_s3_bucket_acl" "data_lake_acl" {
  bucket = aws_s3_bucket.data_lake.id
  acl    = "private"
}

resource "aws_s3_bucket" "logs" {
  bucket = "agency-data-logs"
  tags = {
    Name        = "AgencyDataLogs"
    Environment = "Production"
  }
}

resource "aws_s3_bucket_acl" "logs_acl" {
  bucket = aws_s3_bucket.logs.id
  acl    = "private"
}

# AWS Transfer Family SFTP Server
resource "aws_transfer_server" "sftp_server" {
  endpoint_type           = "PUBLIC"
  identity_provider_type  = "SERVICE_MANAGED"

  tags = {
    Name = "SFTPServer"
  }
}

# IAM Role and Policy for SFTP Access
resource "aws_iam_role" "sftp_access_role" {
  name = "SFTPAcessRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "transfer.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "sftp_access_policy" {
  name = "SFTPAcessPolicy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        Effect   = "Allow",
        Resource = [
          aws_s3_bucket.data_lake.arn
        ]
      },
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ],
        Effect   = "Allow",
        Resource = [
          "${aws_s3_bucket.data_lake.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sftp_role_policy_attach" {
  role       = aws_iam_role.sftp_access_role.name
  policy_arn = aws_iam_policy.sftp_access_policy.arn
}

# SFTP Users for Agencies
resource "aws_transfer_user" "sftp_user" {
  for_each = toset(["agency1", "agency2", "agency3"])

  server_id = aws_transfer_server.sftp_server.id
  user_name = each.key
  role      = aws_iam_role.sftp_access_role.arn
  home_directory = "/${aws_s3_bucket.data_lake.bucket}"

  tags = {
    Name = each.key
  }
}

# CloudWatch Alarms and SNS for Alerts
resource "aws_sns_topic" "sftp_alerts_topic" {
  name = "SFTPAlerts"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.sftp_alerts_topic.arn
  protocol  = "email"
  endpoint  = "your-email@example.com"  # Change to your email
}

resource "aws_cloudwatch_log_group" "sftp_log_group" {
  name = "/aws/sftp"
}

resource "aws_cloudwatch_metric_alarm" "sftp_alarm" {
  alarm_name          = "SFTPMissingData"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfObjects"
  namespace           = "AWS/S3"
  period              = "86400"  # 1 day
  statistic           = "Sum"
  threshold           = "1"

  dimensions = {
    BucketName = aws_s3_bucket.data_lake.bucket
  }

  alarm_actions = [
    aws_sns_topic.sftp_alerts_topic.arn
  ]

  ok_actions = [
    aws_sns_topic.sftp_alerts_topic.arn
  ]

  insufficient_data_actions = [
    aws_sns_topic.sftp_alerts_topic.arn
  ]
}

