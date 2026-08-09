# שליפת אזורי הזמינות הפעילים באזור הנבחר באופן דינמי
data "aws_availability_zones" "available" {
  state = "available"
}

# שימוש במודול הרשמי של AWS ליצירת VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "devops-project-vpc"
  cidr = "10.0.0.0/16"

  # פריסת Subnets על פני 3 אזורי זמינות באופן דינמי
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # הפעלת NAT Gateway יחיד לצורך חיסכון בעלויות בסביבת הפרויקט
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # תגיות קריטיות עבור Kubernetes AWS Load Balancer Controller
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}