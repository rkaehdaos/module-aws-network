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

# 서브넷 
data "aws_availability_zones" "available" {
  state = "available" 
}

# AWS 가용영역
# - 별도의 분리된 데이터센터 의미
# - 배포시 2개 이상 가용영역 사용 → 하나가 다운되도 나머지 영역에서 서비스 중단 없이 작동
# - EKS가 제대로 작동하려면 서로 다른 가용 영역에 서브넷 정의 필요
# - AWS는 공개(인터넷 트래픽 허용) , 사설 서브넷(내부 트래픽만 허용)이 모두 있는 VPC 구성 권장
# - 공개 서브넷 : LB배포 → 인바운드 트래픽 관리  → LB 통과 트래픽은 사설 서브넷의 EKS 마이크로서비스 컨테이너로 라우팅
resource "aws_subnet" "public-subnet-a" {
  vpc_id            = aws_vpc.main.id
  # 서브넷은 VPC 내부 → VPC 범위 내의 CIDR 블록이어야 함 →VPC와 마찬가지로 변수 사용
  cidr_block        = var.public_subnet_a_cidr
  # 가용 영역도 서브넷의 매개변수로 지정
  # 가용 영역 이름을 하드 코딩 하는 대신 영역을 동적으로 선택 가능한 data라는 특수한 영역
  # a에 [0], b에 [1]을 넣는다 
  # 동적 데이터 사용하면 다른 리전에서 인프라를 더 쉽게 가동 
  availability_zone = data.aws_availability_zones.available.names[0]

  
  tags = {
    # 관리자와 운영자가 콘솔을 통해 네트워크 리소스를 쉽게 찾을 수 있도록 이름 태그 추가
    "Name"                                        = "${local.vpc_name}-public-subnet-a"
    # EKS 태그 추가 : AWS 쿠버네티스 서비스가 사용 중인 서브넷과 해당 서브넷이 무엇인지 알 수 있도록
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    # elb 태그 추가 : EKS가 서브넷을 사용하여 ELB를 생성하고 배포 가능하도록 공개 서브넷에 지정
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
    # internal-elb 태그 추가 : 해당 태그로 워크로드가 배포되고 분산 될 수 있음
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


# 마지막 단계 - 서브넷 허용할 트래픽 소스를 정의하는 라우팅 테이블 설정
# ex) 트래픽이 공개 서브넷을 통해 전달되는 방법, 각 서브넷 통신 가능한 방법 설정.
# igw(internet gateway):  사설 클라우드를 공개 인터넷과 연결하는 AWS 네트워크 구성 요소
# 테라폼은 igw 리소스 정의 제공
# 

# 공용 서브넷을 위한 인터넷 게이트웨이 및 라우팅 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id #이전에 생성한  VPC 연결

  tags = {
    Name = "${local.vpc_name}-igw"
  }
}

# 라우팅 규칙 정의 : 게이트웨이에서 서브넷으로 트래픽 라우팅하는 방법을 AWS에게 알리는
# 
resource "aws_route_table" "public-route" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0" #모든 트래픽을 게이트웨이를 통해 처리
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    "Name" = "${local.vpc_name}-public-route"
  }
}

# 공개 서브넷과 라우팅 테이블 간의 연결 생성
resource "aws_route_table_association" "public-a-association" {
  subnet_id      = aws_subnet.public-subnet-a.id
  route_table_id = aws_route_table.public-route.id
}

resource "aws_route_table_association" "public-b-association" {
  subnet_id      = aws_subnet.public-subnet-b.id
  route_table_id = aws_route_table.public-route.id
}


# 공개 서브넷 라우팅 경로가 정의되면 2개의 사설 서브넷에 대한 라우팅 설정 진행
# 사설은 공개서브넷 라우팅 구성보다 더 복잡해질 수 밖에 없다
# ∵ k8s의 pod가 EKS 서비스와 통신할 수 있도록 사설 서브넷에서 인터넷으로 나가는 경로를 정의해야 함
# ∴ 사설 서브넷에서 공개 서브넷에 배포한 igw와 통신할 수 있는 방법이 필요 - NAT 게이트웨이 리소스
# EIP(Elastic IP) : NAT 생성할 떄 할당되는 특별한 IP로 인터넷에서 접근 가능한 실제 네트워크 IP

# 2개의 EIP를 생성하야 NAT에 할당
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

# nat gateway
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
