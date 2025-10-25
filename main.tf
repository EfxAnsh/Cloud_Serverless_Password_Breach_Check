# main.tf - Serverless Password Breach Checker Infrastructure (FINAL IAM FIX)

###################################
# 1. DYNAMODB TABLE & SNS TOPIC
###################################

resource "aws_dynamodb_table" "password_checks" {
  name             = "PasswordChecks-${var.project_name}"
  billing_mode     = "PAY_PER_REQUEST" 
  hash_key         = "UserID" 
  range_key        = "CheckTime"

  attribute {
    name = "UserID"
    type = "S" 
  }
  attribute {
    name = "CheckTime"
    type = "N" 
  }
}

resource "aws_sns_topic" "breach_notification" {
  name = "BreachNotificationTopic-${var.project_name}"
}

###################################
# 2. LAMBDA EXECUTION ROLE & POLICY
###################################

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name               = "PasswordCheckerLambdaRole-${var.project_name}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Custom Policy for DynamoDB and SNS access
data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    effect    = "Allow"
    actions   = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:ap-south-1:${var.account_id}:*"] 
  }
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.password_checks.arn] 
  }
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"] 
    # FIX: Use the wildcard (*) resource for SNS SMS publishing
    resources = ["*"] 
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "PasswordCheckerLambdaPolicy-${var.project_name}"
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

###################################
# 3. LAMBDA FUNCTION
###################################

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "lambda"
  output_path = "lambda_package.zip"
}

resource "aws_lambda_function" "password_checker_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "passwordCheckerLambda-${var.project_name}"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "password_checker.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 10 

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.password_checks.name
      SNS_TOPIC_ARN       = aws_sns_topic.breach_notification.arn
    }
  }
}

###################################
# 4. API GATEWAY (Public Access + CORS)
###################################

resource "aws_api_gateway_rest_api" "api" {
  name        = "PasswordCheckerAPI-${var.project_name}"
  description = "Public serverless API for password breach checking."
}

resource "aws_api_gateway_resource" "check_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "check"
}

resource "aws_api_gateway_method" "check_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.check_resource.id
  http_method   = "POST"
  authorization = "NONE" 
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.check_resource.id
  http_method             = aws_api_gateway_method.check_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.password_checker_lambda.invoke_arn
}

resource "aws_api_gateway_method" "options_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.check_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE" 
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.check_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  type        = "MOCK" 
  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "options_method_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.check_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.check_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = aws_api_gateway_method_response.options_method_response.status_code

  response_templates = {
    "application/json" = ""
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_integration]
}

resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.password_checker_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.check_resource.id,
      aws_api_gateway_method.check_method.id,
      aws_api_gateway_integration.lambda_integration.id,
      aws_api_gateway_method.options_method.id,
      aws_api_gateway_integration.options_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "production_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

###################################
# 5. S3 STATIC WEBSITE HOSTING
###################################

resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "password-checker-frontend-${var.account_id}"
}

resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.frontend_bucket.id

  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "public_access_block" {
  bucket                  = aws_s3_bucket.frontend_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "s3_policy_doc" {
  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend_bucket.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "s3_access_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = data.aws_iam_policy_document.s3_policy_doc.json
  depends_on = [aws_s3_bucket_public_access_block.public_access_block]
}

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend_bucket.id
  key          = "index.html"
  source       = "frontend/index.html"
  content_type = "text/html"
}