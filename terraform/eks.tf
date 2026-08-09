# שימוש במודול v20 המעודכן והמאובטח של AWS EKS
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.35" # הגרסה המעודכנת והנתמכת ב-AWS

  # חיבור ה-EKS לרשת ה-VPC שיצרנו
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # גישת Admin אוטומטית למשתמש שיוצר את האשכול
  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  # תוסף חיוני המאפשר ל-Jenkins לשמור נתונים על דיסק EBS
  cluster_addons = {
    aws-ebs-csi-driver = { most_recent = true }
  }

  # הגדרת שרתי ה-Worker (Node Group)
  eks_managed_node_groups = {
    main = {
      min_size     = 2
      max_size     = 4
      desired_size = 2

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      # הרשאות חיוניות ל-Nodes עבור EBS CSI Driver
      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }

  tags = {
    Environment = "DevOps-Project"
  }
}