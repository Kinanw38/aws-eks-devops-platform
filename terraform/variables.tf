# הגדרת משתנה עבור אזור ה-AWS (ברירת מחדל: us-east-1)
variable "aws_region" {
  description = "אזור AWS שבו יוקמו המשאבים"
  type        = string
  default     = "us-east-1"
}

# הגדרת משתנה עבור שם אשכול ה-Kubernetes
variable "cluster_name" {
  description = "שם אשכול ה-EKS"
  type        = string
  default     = "devops-project-eks"
}