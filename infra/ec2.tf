data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

resource "aws_instance" "main" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.main.id]
  iam_instance_profile        = "LabInstanceProfile"
  key_name                    = "vockey"
  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20
  }

  tags = {
    Name = "team13-main"
  }
}

output "main_public_ip" {
  value = aws_instance.main.public_ip
}
