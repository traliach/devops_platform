
# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

# Public subnet — single AZ is enough for a lab
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false # Elastic IP handles public addressing

  tags = { Name = "${var.project}-public-subnet" }
}

# Internet Gateway — allows the VPC to reach the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project}-igw" }
}

# Route table — sends all outbound traffic to the IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security group — least privilege
# SSH and Jenkins (8080) restricted to your IP only
# HTTP/HTTPS open for Nginx reverse proxy
# Prometheus (9090) and Flask (5000) are internal only — never public
resource "aws_security_group" "platform" {
  name        = "${var.project}-sg"
  description = "devops-platform-lab security group"
  vpc_id      = aws_vpc.main.id

  # SSH — your IPs only (fallback — prefer SSM Session Manager for remote access)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # HTTP — public (Nginx reverse proxy)
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS — public (Nginx reverse proxy)
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Jenkins — your IPs only during setup, proxied via Nginx after
  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Grafana — your IPs only (proxied via Nginx in production)
  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # All outbound traffic allowed (pulling Docker images, AWS API calls, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg" }
}

# Elastic IP — stable public IP that survives instance stop/start
resource "aws_eip" "platform" {
  domain = "vpc"

  tags = { Name = "${var.project}-eip" }
}

# Attach Elastic IP to the instance
resource "aws_eip_association" "platform" {
  instance_id   = aws_instance.platform.id
  allocation_id = aws_eip.platform.id
}
