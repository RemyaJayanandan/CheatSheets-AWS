terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-south-1"
}

# Security Group for EC2 Instances
resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow HTTP and SSH traffic"
  vpc_id      = "vpc-0215cff6cab57ccb5"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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

# Launch Template for EC2 Instances
resource "aws_launch_template" "web_launch_template" {
  name_prefix   = "web-instance-template"
  image_id      = "ami-0522ab6e1ddcc7055" # Replace with your desired AMI
  instance_type = "t2.micro"

  key_name = "aws-keypair"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_sg.id]
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y apache2
              systemctl start apache2
              systemctl enable apache2
              echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html
              EOF
}

# Auto Scaling Group
resource "aws_autoscaling_group" "web_asg" {
  desired_capacity     = 1
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = ["subnet-056c6ccf114ab2079"] # Your subnet ID

  launch_template {
    id      = aws_launch_template.web_launch_template.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "WebServer"
    propagate_at_launch = true
  }
}

# CloudWatch Alarms for Scaling
resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  alarm_name          = "cpu_too_high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70

  alarm_actions = [aws_autoscaling_policy.scale_up_policy.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "scale_down_alarm" {
  alarm_name          = "cpu_too_low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 20

  alarm_actions = [aws_autoscaling_policy.scale_down_policy.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
}

# Scaling Policy
resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "scale-up"
  scaling_adjustment      = 1
  adjustment_type         = "ChangeInCapacity"
  cooldown                = 300
  autoscaling_group_name  = aws_autoscaling_group.web_asg.name
}

resource "aws_autoscaling_policy" "scale_down_policy" {
  name                   = "scale-down"
  scaling_adjustment      = -1
  adjustment_type         = "ChangeInCapacity"
  cooldown                = 300
  autoscaling_group_name  = aws_autoscaling_group.web_asg.name
}
