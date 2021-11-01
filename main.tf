# AWS 공급자 선언 - 테라폼이 AWS API와 통신하기 위한 라이브러리를 다운받아 설치해야함을 선언
# (버전에 따라 달라진다는데 과연)
provider "aws" {
  region = var.aws_region
}

# locals 블럭을 사용해서 2개의 로컬 변수 지정
# - 로컬 변수는 AWS 콘솔에서 환경별 리소스 구별하는데 도움이 되는 이름 정의
# - 동일한 AWS 계정에서 여러 환경 생성시 고유 이름 보장하므로 중요
locals {
  vpc_name     = "${var.env_name} ${var.vpc_name}"
  cluster_name = "${var.cluster_name}-${var.env_name}"
}

## AWS VPC 생성 관련 정의
# 여기선 CIDR 블록과 태그 지정
# 몇가지 변수 사용 → 변경 가능한 값 → 모듈 재사용 가능
resource "aws_vpc" "main" {
  cidr_block = var.main_vpc_cidr # CIDR 블록 변수정의 
  enable_dns_support = true
  enable_dns_hostnames = true
  # 태그 추가
  # 리소스 태그 추가 → 리소스 그룹을 쉽게 식별/관리 가능
  # 자동화된 작업이나 특정 방식으로 관리할 리소스 식별시 유용
  # 쿠버네티스 클러스터를 식별하는 쿠버네티스 태그도 정의
  # (쿠버 클러스터는 EKS 노드 그룹 정의에서 정의)할 예정
  
  tags = {
    "Name"                                        = local.vpc_name,
    "kubernetes.io/cluster/${local.cluster_name}" = "shared", # 이름태그도 변수
  }
}

data "aws_availability_zones" "available" {
  state = "available" 
}

resource "aws_subnet" "public-subnet-a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_a_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    "Name"                                        = "${local.vpc_name}-public-subnet-a"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
}

resource "aws_subnet" "public-subnet-b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_b_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    "Name"                                        = "${local.vpc_name}-public-subnet-b"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
}

resource "aws_subnet" "private-subnet-a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_a_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    "Name"                                        = "${local.vpc_name}-private-subnet-a"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_subnet" "private-subnet-b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_b_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    "Name"                                        = "${local.vpc_name}-private-subnet-b"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.vpc_name}-igw"
  }
}

resource "aws_route_table" "public-route" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    "Name" = "${local.vpc_name}-public-route"
  }
}

resource "aws_route_table_association" "public-a-association" {
  subnet_id      = aws_subnet.public-subnet-a.id
  route_table_id = aws_route_table.public-route.id
}

resource "aws_route_table_association" "public-b-association" {
  subnet_id      = aws_subnet.public-subnet-b.id
  route_table_id = aws_route_table.public-route.id
}

resource "aws_eip" "nat-a" {
  vpc = true
  tags = {
    "Name" = "${local.vpc_name}-NAT-a"
  }
}

resource "aws_eip" "nat-b" {
  vpc = true
  tags = {
    "Name" = "${local.vpc_name}-NAT-b"
  }
}

resource "aws_nat_gateway" "nat-gw-a" {
  allocation_id = aws_eip.nat-a.id
  subnet_id     = aws_subnet.public-subnet-a.id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    "Name" = "${local.vpc_name}-NAT-gw-a"
  }
}

resource "aws_nat_gateway" "nat-gw-b" {
  allocation_id = aws_eip.nat-b.id
  subnet_id     = aws_subnet.public-subnet-b.id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    "Name" = "${local.vpc_name}-NAT-gw-b"
  }
}

resource "aws_route_table" "private-route-a" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-gw-a.id
  }

  tags = {
    "Name" = "${local.vpc_name}-private-route-a"
  }
}

resource "aws_route_table" "private-route-b" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-gw-b.id
  }

  tags = {
    "Name" = "${local.vpc_name}-private-route-b"
  }
}

resource "aws_route_table_association" "private-a-association" {
  subnet_id      = aws_subnet.private-subnet-a.id
  route_table_id = aws_route_table.private-route-a.id
}

resource "aws_route_table_association" "private-b-association" {
  subnet_id      = aws_subnet.private-subnet-b.id
  route_table_id = aws_route_table.private-route-b.id
}

# Create a Route 53 zone for DNS support inside the VPC
resource "aws_route53_zone" "private-zone" {
  # AWS requires a lowercase name. 
  #name = "lower(${var.env_name}.${var.vpc_name}.com)"
  name = "${var.env_name}.${var.vpc_name}.com"
  #name = "testing.com"
  force_destroy = true

  vpc {
    vpc_id = aws_vpc.main.id
  }
}
