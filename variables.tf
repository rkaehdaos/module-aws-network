
# 환경 이름
variable "env_name" {
  type = string
}

# 리전 변수
variable "aws_region" {
  type = string
}

#vpc 이름 변수
variable "vpc_name" {
  type    = string
  default = "ms-up-running"
}

# CIDR 블록 변수
variable "main_vpc_cidr" {
  type = string
}

# 서브넷은 VPC 범위 내의 CIDR 블록
variable "public_subnet_a_cidr" {
  type = string
}

variable "public_subnet_b_cidr" {
  type = string
}

variable "private_subnet_a_cidr" {
  type = string
}

variable "private_subnet_b_cidr" {
  type = string
}

# k8s 클러스터 이름
variable "cluster_name" {
  type = string
}