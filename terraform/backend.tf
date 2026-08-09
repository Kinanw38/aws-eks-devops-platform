# הגדרת ה-Backend לשמירת ה-State בענן S3 עם מנגנון נעילה ב-DynamoDB
terraform {
  backend "s3" {
    # הערכים (bucket, region, dynamodb_table) יוזרקו דינמית בזמן הרצת terraform init
    key     = "eks/terraform.tfstate"
    encrypt = true
  }
}