provider "aws" {
  region = "us-east-1"  # Change this to your preferred AWS region
}

# Generate a key pair for SSH access
resource "aws_key_pair" "Key-pair" {
  key_name   = "Key-pair-${random_id.ssh_key.hex}"  # Unique name
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "random_id" "ssh_key" {
  byte_length = 4
}


# Security group for EC2 instance
resource "aws_security_group" "dr_sg" {
  name        = "dr-security-group"
  description = "Allow HTTP and SSH access"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allows HTTP access from anywhere
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allows SSH access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch EC2 instance hosting the website
resource "aws_instance" "primary_server" {
  ami           = "ami-00f747470ff841d9f"  # Replace with a valid AMI ID
  instance_type = "t2.micro"       # Cost-effective instance type
  key_name      = "Key-pair"
  security_groups = [aws_security_group.dr_sg.name]

  user_data = <<-EOF
              #!/bin/bash
              echo "hellothere" > /var/www/html/index.html
              sudo yum install -y httpd
              sudo systemctl start httpd
              sudo systemctl enable httpd
              EOF

  tags = {
    Name = "Primary-Server"
  }
}

# Auto Scaling Group & Launch Configuration
resource "aws_launch_template" "dr_lt" {
  name_prefix   = "dr-launch-template"
  image_id      = "ami-00f747470ff841d9f"  # Replace with a valid AMI
  instance_type = "t2.micro"
  key_name      = "Key-pair"

  network_interfaces {
    security_groups = [aws_security_group.dr_sg.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "hellothere" > /var/www/html/index.html
              sudo yum install -y httpd
              sudo systemctl start httpd
              sudo systemctl enable httpd
              EOF
              )
}

resource "aws_autoscaling_group" "dr_asg" {
  desired_capacity     = 1
  max_size             = 2
  min_size             = 1
  vpc_zone_identifier  = ["subnet-01f8cbdefe7a74010"]

  launch_template {
    id      = aws_launch_template.dr_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "DR-Backup-Server"
    propagate_at_launch = true
  }
}


# CloudWatch Alarm for failure detection
resource "aws_cloudwatch_metric_alarm" "instance_down" {
  alarm_name          = "instance-down-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name        = "StatusCheckFailed_Instance"
  namespace          = "AWS/EC2"
  period            = "300"
  statistic        = "Average"
  threshold       = "1"
  alarm_actions  = [aws_autoscaling_group.dr_asg.arn]
  dimensions = {
    InstanceId = aws_instance.primary_server.id
  }
}

# S3 bucket for storing snapshots (optional)
resource "aws_s3_bucket" "dr_snapshots" {
  bucket = "dr-snapshots-bucket"
}

resource "aws_s3_bucket_lifecycle_configuration" "dr_snapshots_lifecycle" {
  bucket = aws_s3_bucket.dr_snapshots.id

  rule {
    id     = "delete_old_backups"
    status = "Enabled"

    expiration {
      days = 7
    }
  }
}

