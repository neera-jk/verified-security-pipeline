terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "team13-verified-security-pipeline"
    }
  }
}

variable "team_ips" {
  description = "Public IPs allowed to SSH to the main instance, each in CIDR form ending in /32"
  type        = list(string)
}

# The reports bucket is created once outside Terraform and referenced by name.
# Learner Lab's service control policy denies s3:GetBucketObjectLockConfiguration,
# and the aws_s3_bucket resource reads that setting after every create and refresh,
# so Terraform cannot manage the bucket resource itself in this account.
variable "reports_bucket_name" {
  description = "Name of the existing reports bucket"
  type        = string
  default     = "team13-vsp-reports-33c3b3e1"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "team13-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "team13-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "team13-public-a"
  }
}

resource "aws_subnet" "honeypot_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "team13-honeypot-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "team13-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "honeypot_b" {
  subnet_id      = aws_subnet.honeypot_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_network_acl" "honeypot" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.honeypot_b.id]

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = aws_subnet.public_a.cidr_block
    from_port  = 2222
    to_port    = 2222
  }

  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    Name = "team13-honeypot-nacl"
  }
}

resource "aws_security_group" "main" {
  name        = "team13-main-sg"
  description = "Main instance, dashboard on 80, SSH from team IPs only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Dashboard"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from team IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.team_ips
  }

  egress {
    description = "Pull images and code, call AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "team13-main-sg"
  }
}

resource "aws_security_group" "honeypot" {
  name        = "team13-honeypot-sg"
  description = "Honeypot, fake SSH open to all, admin 2222 from main SG only, no egress"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Fake SSH for bots"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "Admin and log pull from main instance"
    from_port       = 2222
    to_port         = 2222
    protocol        = "tcp"
    security_groups = [aws_security_group.main.id]
  }

  egress = []

  tags = {
    Name = "team13-honeypot-sg"
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = var.reports_bucket_name
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "scan_index" {
  name         = "team13-scan-index"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sha"

  attribute {
    name = "sha"
    type = "S"
  }

  tags = {
    Name = "team13-scan-index"
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_a_id" {
  value = aws_subnet.public_a.id
}

output "honeypot_subnet_b_id" {
  value = aws_subnet.honeypot_b.id
}

output "main_sg_id" {
  value = aws_security_group.main.id
}

output "honeypot_sg_id" {
  value = aws_security_group.honeypot.id
}

output "reports_bucket" {
  value = var.reports_bucket_name
}

output "scan_index_table" {
  value = aws_dynamodb_table.scan_index.name
}