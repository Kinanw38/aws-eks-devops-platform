# הגדרת גרסאות ה-Terraform והספקים (Providers) הנדרשים
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# הגדרת חיבור לספק AWS עם תגיות ברירת מחדל לכל המשאבים שייווצרו
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "DevOps-Project"
      ManagedBy   = "Terraform"
    }
  }
}