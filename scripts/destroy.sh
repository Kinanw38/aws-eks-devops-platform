#!/usr/bin/env bash
set -e
export AWS_PAGER=""

# צבעים ועיצוב פלט
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="tfstate-${ACCOUNT_ID}-${REGION}"
DYNAMO_TABLE="tflocks-${ACCOUNT_ID}"
CLUSTER_NAME="devops-project-eks"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo -e "${RED}======================================================================"${NC}
echo -e "${BOLD} ⚠️  WARNING: Destroying DevOps Project Infrastructure & Resources${NC}"
echo -e "${RED} Account: ${ACCOUNT_ID} | Region: ${REGION} | Cluster: ${CLUSTER_NAME}${NC}"
echo -e "${RED}======================================================================"${NC}

# 1. ניקוי משאבי Helm ו-Kubernetes
echo -e "\n${YELLOW}==> [STEP 1/4] Uninstalling Helm Releases and Application Resources...${NC}"
if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1 || true

  echo "--> Uninstalling Helm releases..."
  helm uninstall jenkins -n devops 2>/dev/null || true
  helm uninstall prometheus -n monitoring 2>/dev/null || true
  helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true

  echo "--> Removing LoadBalancers, PVCs, Ingresses, and Namespaces..."
  kubectl delete ingress --all --all-namespaces --timeout=30s 2>/dev/null || true
  kubectl delete pvc --all -n devops --timeout=30s 2>/dev/null || true
  kubectl delete pvc --all -n monitoring --timeout=30s 2>/dev/null || true
  kubectl delete pv --all --timeout=30s 2>/dev/null || true
  kubectl delete svc --field-selector spec.type=LoadBalancer --all-namespaces --timeout=30s 2>/dev/null || true

  kubectl delete ns devops monitoring ingress-nginx --timeout=45s --force --grace-period=0 2>/dev/null || true

  echo "--> Waiting 20 seconds for AWS Load Balancers to detach completely..."
  sleep 20
else
  echo "--> EKS Cluster does not exist or is already deleted. Skipping K8s cleanup."
fi

# 2. הרצת terraform destroy
cd "${PROJECT_ROOT}/terraform"

echo -e "\n${YELLOW}==> [STEP 2/4] Running Terraform Destroy...${NC}"
terraform destroy -auto-approve

# 3. ניקוי מוחלט של ה-S3 Bucket
echo -e "\n${YELLOW}==> [STEP 3/4] Force-deleting S3 State Bucket (${BUCKET_NAME})...${NC}"
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'Versions[].{Key: Key, VersionId: VersionId}' --output text 2>/dev/null | while read -r key version_id; do
    if [ -n "$key" ] && [ -n "$version_id" ] && [ "$key" != "None" ]; then
      aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id" >/dev/null 2>&1 || true
    fi
  done

  aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'DeleteMarkers[].{Key: Key, VersionId: VersionId}' --output text 2>/dev/null | while read -r key version_id; do
    if [ -n "$key" ] && [ -n "$version_id" ] && [ "$key" != "None" ]; then
      aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id" >/dev/null 2>&1 || true
    fi
  done

  aws s3 rb "s3://${BUCKET_NAME}" --force 2>/dev/null || true
  echo -e "${GREEN}--> S3 Bucket deleted successfully.${NC}"
else
  echo "--> S3 Bucket does not exist."
fi

# 4. מחיקת טבלת DynamoDB
echo -e "\n${YELLOW}==> [STEP 4/4] Deleting DynamoDB Lock Table (${DYNAMO_TABLE})...${NC}"
if aws dynamodb describe-table --table-name "$DYNAMO_TABLE" --region "$REGION" >/dev/null 2>&1; then
  aws dynamodb delete-table --table-name "$DYNAMO_TABLE" --region "$REGION" >/dev/null
  echo -e "${GREEN}--> DynamoDB Table deleted successfully.${NC}"
else
  echo "--> DynamoDB Table does not exist."
fi

echo -e "\n${CYAN}======================================================================"${NC}
echo -e "${GREEN}${BOLD} 🧹 Clean Teardown Completed! Zero Footprint Left on AWS.${NC}"
echo -e "${CYAN}======================================================================"${NC}