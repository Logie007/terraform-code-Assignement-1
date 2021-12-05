provider "aws" {
region     = "ap-southeast-1"
access_key = ""
secret_key = ""
}
terraform {
required_version = ">= 0.12"
}
 
# Creating VPC
resource "aws_vpc" "vpc" {
cidr_block       = "10.0.0.0/16"
instance_tenancy = "default"
 
tags = {
 Name = "Main.VPC"
}
enable_dns_hostnames = true
}
#  Creating public Subnet
resource "aws_subnet" "public_subnet" {
depends_on = [
 aws_vpc.vpc,
]
vpc_id     = aws_vpc.vpc.id
cidr_block = "10.0.1.0/24"
availability_zone_id = "apse1-az1"
tags = {
 Name = "Public.Subnet"
}
map_public_ip_on_launch = true
}

# Creating Private Subnet
resource "aws_subnet" "private_subnet" {
depends_on = [
 aws_vpc.vpc,
]
vpc_id     = aws_vpc.vpc.id
cidr_block = "10.0.2.0/24"
availability_zone_id = "apse1-az2"
tags = {
 Name = "Private.Subnet"
}
}

 
# Creating Internet Gateway
resource "aws_internet_gateway" "internet_gateway" {
depends_on = [
 aws_vpc.vpc,
]
vpc_id = aws_vpc.vpc.id
tags = {
 Name = "Internet.gateway"
}
}
# Route table for internet gateway
resource "aws_route_table" "IG_route_table" {
depends_on = [
 aws_vpc.vpc,
 aws_internet_gateway.internet_gateway,
]
vpc_id = aws_vpc.vpc.id
route {
 cidr_block = "0.0.0.0/0"
 gateway_id = aws_internet_gateway.internet_gateway.id
}
tags = {
 Name = "Route.table.IG" 
}
}
# associate route table to public subnet
resource "aws_route_table_association" "associate_routetable_to_public_subnet" {
depends_on = [
 aws_subnet.public_subnet,
 aws_route_table.IG_route_table,
]
subnet_id      = aws_subnet.public_subnet.id
route_table_id = aws_route_table.IG_route_table.id
}
# Assigning Elastic IP
resource "aws_eip" "elastic_ip" {
vpc      = true
tags = {
 Name = "eip"
}
}
# NAT gateway
resource "aws_nat_gateway" "nat_gateway" {
depends_on = [
 aws_subnet.public_subnet,
 aws_eip.elastic_ip,
]
allocation_id = aws_eip.elastic_ip.id
subnet_id     = aws_subnet.public_subnet.id
tags = {
 Name = "nat.gateway"
}
}
# Private subnet association
resource "aws_route_table" "NAT_route_table" {
depends_on = [
 aws_vpc.vpc,
 aws_nat_gateway.nat_gateway,
]
vpc_id = aws_vpc.vpc.id
route {
 cidr_block = "0.0.0.0/0"
 gateway_id = aws_nat_gateway.nat_gateway.id
}
tags = {
 Name = "Route.table.Nat"
}
}
# associate route table to private subnet
resource "aws_route_table_association" "associate_routetable_to_private_subnet" {
depends_on = [
 aws_subnet.private_subnet,
 aws_route_table.NAT_route_table,
]
subnet_id      = aws_subnet.private_subnet.id
route_table_id = aws_route_table.NAT_route_table.id
}
 
#bastion host security group
resource "aws_security_group" "sg_frontend" {
depends_on = [
 aws_vpc.vpc,
]
name        = "Security Group for Server A"
description = "Allow SSH and tcp 80"
vpc_id      = aws_vpc.vpc.id
ingress {
 description = "allow SSH"
 from_port   = 22
 to_port     = 22
 protocol    = "tcp"
 cidr_blocks = ["0.0.0.0/0"]
}
ingress {
    description = "allow TCP"
    from_port   = 80
    to_port     = 80
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
# Frontend server ec2 instance
resource "aws_instance" "frontend" {
depends_on = [
 aws_security_group.sg_frontend,
]
ami = "ami-0dc5785603ad4ff54"
instance_type = "t2.micro"
key_name = "test" 
vpc_security_group_ids = [aws_security_group.sg_frontend.id]
subnet_id = aws_subnet.public_subnet.id
user_data = <<EOF
            #! /bin/bash
            yum update
            yum install docker -y
            systemctl restart docker
            systemctl enable docker
            docker pull nginx:latest
            docker run -it --rm -d -p 80:80 --name web nginx
  EOF

tags = {
   Name = "Server A"
}
}
resource "aws_security_group" "sg_backend" {
  depends_on = [
    aws_vpc.vpc,
  ]

  name        = "Security Group for Server B"
  description = "Allow ssh from server A"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [aws_security_group.sg_frontend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# backend ec2 instance
resource "aws_instance" "backend" {
  depends_on = [
    aws_security_group.sg_backend,
  ]
  ami = "ami-0dc5785603ad4ff54"
  instance_type = "t2.micro"
  key_name = "test"
  vpc_security_group_ids = [aws_security_group.sg_backend.id]
  subnet_id = aws_subnet.private_subnet.id
  
  tags = {
      Name = "Server B"
  }
}
