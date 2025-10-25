# outputs.tf (Simplified - No Cognito)

output "api_gateway_url" {
  description = "The base URL for the unauthenticated API endpoint."
  value       = "${aws_api_gateway_stage.production_stage.invoke_url}/check"
}

output "s3_website_endpoint" {
  description = "The URL for the static frontend website."
  value       = aws_s3_bucket_website_configuration.website_config.website_endpoint
}

output "sns_topic_arn" {
  description = "The ARN of the SNS Topic used by Lambda for email notification."
  value       = aws_sns_topic.breach_notification.arn
}