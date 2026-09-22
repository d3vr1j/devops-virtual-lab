provider "aws" {
  region = "us-east-1"
}

# ADDED: look up latest Amazon Linux 2023 AMI instead of hardcoding one
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ADDED: generate SSH key pair so Ansible can connect
resource "tls_private_key" "lab" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab" {
  key_name   = "devops-lab-key"
  public_key = tls_private_key.lab.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.lab.private_key_pem
  filename        = "${path.module}/../ansible/my-key.pem"
  file_permission = "0400"
}

# ADDED: allow SSH in (lab only; destroy after use)
resource "aws_security_group" "lab_sg" {
  name = "devops-lab-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ADDED: SSH on 443 because local network blocks port 22
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "devops_server" {
  ami                    = data.aws_ami.amazon_linux.id   # CHANGED: was hardcoded AMI
  instance_type          = "t3.micro"                     # CHANGED: t2.micro not free-tier eligible
  key_name               = aws_key_pair.lab.key_name      # CHANGED: was "my-key"
  vpc_security_group_ids = [aws_security_group.lab_sg.id] # ADDED

  # ADDED: make sshd listen on both 22 and 443
  user_data = <<-USERDATA
    #!/bin/bash
    printf "Port 22\nPort 443\n" > /etc/ssh/sshd_config.d/10-ports.conf
    systemctl restart sshd
  USERDATA

  user_data_replace_on_change = true # ADDED: recreate instance so user_data runs

  tags = {
    Name = "DevOps-Lab-Server"
  }
}

# ADDED: print public IP for the Ansible inventory
output "public_ip" {
  value = aws_instance.devops_server.public_ip
}
