# Configure the AWS Provider
provider "aws" {
  region  = "us-east-1"
   access_key = #remove
  secret_key = #remove
}


resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16" #define IP blocks for vpc to work with
  instance_tenancy = "default"

  tags = {
    Name = "main"
  }
}

#security group
resource "aws_security_group" "secgroup" {
  name        = "secgroup"
  vpc_id      = "${aws_vpc.main.id}"

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [ "${aws_vpc.main.cidr_block}" ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = {
    Name = "secgroup"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.main.id}"
  tags = {
    Name = "main"
  }
}

# Declare the data source
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "subnet1" {
  vpc_id     = "${aws_vpc.main.id}" #bind to vpc
  cidr_block = "10.0.0.0/24" #define an IP zone
  availability_zone = "${data.aws_availability_zones.available.names[0]}" #bind to availability_zone
  tags = {
    Name = "subnet1"
  }
}

resource "aws_subnet" "subnet2" {
  vpc_id     = "${aws_vpc.main.id}"
  cidr_block = "10.0.1.0/24"
  availability_zone = "${data.aws_availability_zones.available.names[1]}"
  tags = {
    Name = "subnet2"
  }
}

#subnet group
resource "aws_db_subnet_group" "default" {
  name       = "main"
  subnet_ids = ["${aws_subnet.subnet1.id}", "${aws_subnet.subnet2.id}"]

  tags = {
    Name = "My DB subnet group"
  }
}

#ec2, instance 1
resource "aws_instance" "instance1" {
	ami = "ami-2757f631" #amazon machine image
	instance_type = "t2.micro" #type of server
	subnet_id = "${aws_subnet.subnet1.id}"
	vpc_security_group_ids = ["${aws_security_group.secgroup.id}"]
}

#ec2, instance 2
resource "aws_instance" "instance2" {
	ami = "ami-2757f631" #amazon machine image
	instance_type = "t2.micro" #type of server
	subnet_id = "${aws_subnet.subnet2.id}"
	vpc_security_group_ids = ["${aws_security_group.secgroup.id}"] 
}

# Create a new load balancer
resource "aws_elb" "hw1-elb" {
  name               = "hw1-tf-elb"
  subnets = ["${aws_subnet.subnet1.id}"]


  
  listener {
    instance_port     = 8000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }


  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:8000/"
    interval            = 30
  }

  instances                   = ["${aws_instance.instance1.id}", "${aws_instance.instance2.id}"]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "hw1-tf-elb"
  }
}

#database instance
resource "aws_db_instance" "database" {
  db_subnet_group_name = "${aws_db_subnet_group.default.name}"
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  name                 = "mydb"
  username             = "" #removed
  password             = "" #removed
  parameter_group_name = "default.mysql5.7"
  vpc_security_group_ids = ["${aws_security_group.secgroup.id}"]
  skip_final_snapshot = "true"
}


#Had to create launch configs for instances + Autoscaling aspects

resource "aws_launch_configuration" "as_conf" {
  name_prefix             = "auto-scale"
  image_id                = "ami-04533969992547875"
  instance_type           = "t2.micro"
  security_groups         = ["${aws_security_group.lb_security_group.id}"]
  lifecycle {
    create_before_destroy = true
  }
}

# 
resource "aws_autoscaling_group" "ec2_scale_group" {
  name                            = "ec2_auto_scale_group"
  vpc_zone_identifier             = ["${aws_subnet.Private1a.id}","${aws_subnet.privateSB3.id}"]
  launch_configuration            = "${aws_launch_configuration.as_conf.name}"
  min_size                        = 2
  max_size                        = 8
  health_check_grace_period       = 250
  health_check_type               = "ELB"
  force_delete                    = true
  lifecycle {
    create_before_destroy         = true
  }
}




resource "aws_autoscaling_policy" "ec2_scale_down" {
  name                   = "ec2_scale_down"
  scaling_adjustment     = "-1"               
  adjustment_type        = "ChangeInCapacity"
  cooldown               = "250"
  autoscaling_group_name = "${aws_autoscaling_group.ec2_scaling_group.name}"
  policy_type            = "SimpleScaling"
}





resource "aws_autoscaling_policy" "ec2_scale_up" {
  name                   = "ec2_scale_up"
  scaling_adjustment     = "3"              
  adjustment_type        = "ChangeInCapacity"
  cooldown               = "250"
  autoscaling_group_name = "${aws_autoscaling_group.ec2_scaling_group.name}"
  policy_type            = "SimpleScaling"
}