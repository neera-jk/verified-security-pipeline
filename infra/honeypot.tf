resource "aws_instance" "honeypot" {
  ami                         = "ami-062caee4b7b602eb0" # Amazon Linux 2023, pinned 2026-11-23
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.honeypot_b.id
  vpc_security_group_ids      = [aws_security_group.honeypot.id]
  associate_public_ip_address = true
  user_data                   = file("${path.module}/honeypot_user_data.sh")
  user_data_replace_on_change = true

  # No iam_instance_profile and no key_name on purpose. The security group has
  # no egress rules, so this instance could not reach an AWS API even if it had
  # credentials, and there is no sshd for a key to authenticate against.

  root_block_device {
    volume_size = 8
  }

  tags = {
    Name = "team13-honeypot"
  }
}

output "honeypot_public_ip" {
  value = aws_instance.honeypot.public_ip
}

output "honeypot_private_ip" {
  value = aws_instance.honeypot.private_ip
}
