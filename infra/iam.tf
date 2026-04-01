# IAM role for the EC2 instance
# No permissions attached yet — the instance profile is the correct pattern
# for granting AWS API access later without storing access keys on the server
resource "aws_iam_role" "ec2" {
  name = "${var.project}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = { Name = "${var.project}-ec2-role" }
}

# SSM Session Manager — allows connecting to the instance from anywhere
# via AWS CLI or console without needing port 22 open or a fixed IP
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile — the container that attaches the IAM role to the EC2 instance
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2.name
}
