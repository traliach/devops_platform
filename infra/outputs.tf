output "public_ip" {
  description = "Elastic IP — stable public IP for the platform server"
  value       = aws_eip.platform.public_ip
}

output "instance_id" {
  description = "EC2 instance ID — use this to stop/start via AWS CLI"
  value       = aws_instance.platform.id
}

output "ssh_command" {
  description = "Ready-to-use SSH command (null if no key pair provided — use SSM instead)"
  value       = var.public_key != null ? "ssh -i ~/.ssh/devops-platform-lab-key ec2-user@${aws_eip.platform.public_ip}" : "No key pair — connect via: aws ssm start-session --target ${aws_instance.platform.id} --region ${var.aws_region}"
}

output "stop_command" {
  description = "AWS CLI command to stop the instance (cost control)"
  value       = "aws ec2 stop-instances --instance-ids ${aws_instance.platform.id} --region ${var.aws_region}"
}

output "start_command" {
  description = "AWS CLI command to start the instance"
  value       = "aws ec2 start-instances --instance-ids ${aws_instance.platform.id} --region ${var.aws_region}"
}
