#!/usr/bin/env bash
set -e
export AWS_PAGER=""

# צבעים ועיצוב פלט
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="tfstate-${ACCOUNT_ID}-${REGION}"
DYNAMO_TABLE="tflocks-${ACCOUNT_ID}"
CLUSTER_NAME="devops-project-eks"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo -e "${CYAN}======================================================================"${NC}
echo -e "${BOLD} 🚀 Starting Complete DevOps Infrastructure & App Deployment${NC}"
echo -e "${CYAN}======================================================================"${NC}

# STEP 0: אימות זהות מול Docker Hub API וזיהוי Git Repo
echo -e "\n${GREEN}==> [STEP 0/8] Validating Docker Hub Credentials & Git Repository...${NC}"

# 1. זיהוי/בקשת Git Repository URL
GIT_REPO_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
while [ -z "$GIT_REPO_URL" ]; do
  echo -e "${YELLOW}🔗 Git Remote URL not detected.${NC}"
  read -p "Enter Git Repository URL (e.g. https://github.com/user/repo.git): " GIT_REPO_URL
done
echo -e "==> Git Repository: ${CYAN}${GIT_REPO_URL}${NC}"

# 2. אימות מול Docker Hub API בלולאה
while true; do
  if [ -z "$DOCKERHUB_USERNAME" ]; then
    read -p "Enter Docker Hub Username: " DOCKERHUB_USERNAME
  fi

  if [ -z "$DOCKERHUB_PAT" ]; then
    read -sp "Enter Docker Hub Personal Access Token (PAT): " DOCKERHUB_PAT
    echo ""
  fi

  # בדיקת תקינות הקלט הריק
  if [ -z "$DOCKERHUB_USERNAME" ] || [ -z "$DOCKERHUB_PAT" ]; then
    echo -e "${RED}❌ Username and PAT cannot be empty. Please try again.${NC}\n"
    DOCKERHUB_USERNAME=""
    DOCKERHUB_PAT=""
    continue
  fi

  echo "==> Verifying credentials with Docker Hub API..."
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"${DOCKERHUB_USERNAME}\", \"password\": \"${DOCKERHUB_PAT}\"}" \
    https://hub.docker.com/v2/users/login/ || echo "000")

  if [ "$HTTP_STATUS" -eq 200 ]; then
    echo -e "${GREEN}✓ Docker Hub authentication successful!${NC}"
    break
  else
    echo -e "${RED}❌ Invalid Docker Hub Username or PAT (HTTP ${HTTP_STATUS}). Please try again.${NC}\n"
    DOCKERHUB_USERNAME=""
    DOCKERHUB_PAT=""
  fi
done

# 1. זיהוי חשבון AWS ויצירת Storage ל-Terraform State
echo -e "\n${GREEN}==> [STEP 1/8] Detecting AWS Account: ${ACCOUNT_ID} in Region: ${REGION}${NC}"

if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "==> Creating S3 Bucket for State storage: ${BUCKET_NAME}"
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"
  aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled
else
  echo "==> S3 Bucket already exists: ${BUCKET_NAME}"
fi

if ! aws dynamodb describe-table --table-name "$DYNAMO_TABLE" --region "$REGION" >/dev/null 2>&1; then
  echo "==> Creating DynamoDB Table for State locking: ${DYNAMO_TABLE}"
  aws dynamodb create-table \
    --table-name "$DYNAMO_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"
  aws dynamodb wait table-exists --table-name "$DYNAMO_TABLE" --region "$REGION"
else
  echo "==> DynamoDB Table already exists: ${DYNAMO_TABLE}"
fi

# 2. הרצת Terraform
cd "${PROJECT_ROOT}/terraform"

echo -e "\n${GREEN}==> [STEP 2/8] Initializing Terraform...${NC}"
terraform init \
  -backend-config="bucket=${BUCKET_NAME}" \
  -backend-config="key=eks/terraform.tfstate" \
  -backend-config="region=${REGION}" \
  -backend-config="dynamodb_table=${DYNAMO_TABLE}"

echo -e "\n${GREEN}==> [STEP 3/8] Applying Infrastructure via Terraform...${NC}"
terraform apply -auto-approve

# 3. חיבור kubectl לקלאסטר
echo -e "\n${GREEN}==> [STEP 4/8] Updating kubectl context for EKS Cluster...${NC}"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

# 4. התקנת תוספי הליבה ב-Helm & Metrics Server
echo -e "\n${GREEN}==> [STEP 5/8] Installing Core Addons (Metrics Server & NGINX Ingress Controller)...${NC}"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jenkins https://charts.jenkins.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace --wait

# 5. יצירת Namespace והזרקת ה-Secrets
echo -e "\n${GREEN}==> [STEP 6/8] Creating Namespace & Injecting Live Kubernetes Secrets...${NC}"
kubectl create namespace devops --dry-run=client -o yaml | kubectl apply -f -

kubectl delete secret dockerhub-secret -n devops --ignore-not-found >/dev/null 2>&1
kubectl create secret docker-registry dockerhub-secret \
  --namespace=devops \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username="${DOCKERHUB_USERNAME}" \
  --docker-password="${DOCKERHUB_PAT}"

echo "==> Generating Self-Signed TLS Certificate for Ingress HTTPS..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=devops.local/O=DevOpsProject" 2>/dev/null

kubectl delete secret devops-rest-api-tls -n devops --ignore-not-found >/dev/null 2>&1
kubectl create secret tls devops-rest-api-tls \
  --cert=/tmp/tls.crt \
  --key=/tmp/tls.key \
  -n devops
rm -f /tmp/tls.key /tmp/tls.crt

# 6. החלת המניפסטים הסטטיים של האפליקציה
echo -e "\n${GREEN}==> [STEP 7/8] Applying Application Kubernetes Manifests...${NC}"
kubectl apply -f "${PROJECT_ROOT}/kubernetes/"

# 7. התקנת Jenkins ו-Prometheus Stack
echo -e "\n${GREEN}==> [STEP 8/8] Installing Jenkins & Monitoring Stack via Helm...${NC}"
helm upgrade --install jenkins jenkins/jenkins \
  --namespace devops \
  -f "${PROJECT_ROOT}/jenkins/values.yaml" \
  --set controller.extraEnvVars[0].name=DOCKER_HUB_USER \
  --set controller.extraEnvVars[0].value="${DOCKERHUB_USERNAME}" \
  --set controller.extraEnvVars[1].name=DOCKER_HUB_PAT \
  --set controller.extraEnvVars[1].value="${DOCKERHUB_PAT}" \
  --set controller.extraEnvVars[2].name=GIT_REPO_URL \
  --set controller.extraEnvVars[2].value="${GIT_REPO_URL}"

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

# 8. המתנה לזמינות האפליקציה והדפסת תוצאות
echo -e "\n${YELLOW}==> Waiting for Application Deployment to be Ready...${NC}"
kubectl rollout status deployment/devops-rest-api -n devops --timeout=180s

echo -e "\n${YELLOW}==> Fetching AWS External LoadBalancer Address...${NC}"
LB_HOST=""
RETRY_COUNT=0
while [ -z "$LB_HOST" ] && [ $RETRY_COUNT -lt 30 ]; do
  LB_HOST=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -z "$LB_HOST" ] && sleep 5 && RETRY_COUNT=$((RETRY_COUNT+1))
done

JENKINS_PASSWORD=$(kubectl get secret --namespace devops jenkins -o jsonpath="{.data.jenkins-admin-password}" 2>/dev/null | base64 --decode || echo "Check K8s Secret")

echo -e "\n${CYAN}======================================================================"${NC}
echo -e "${GREEN}${BOLD} 🎉 End-to-End Environment Deployed Successfully!${NC}"
echo -e "${CYAN}======================================================================"${NC}
echo -e "${BOLD}🌐 REST API Base URL (HTTPS):${NC}    https://${LB_HOST}/"
echo -e "${BOLD}📄 Injected File Endpoint:${NC}      https://${LB_HOST}/injected-file"
echo -e "${BOLD}❤️ Health Check Endpoint:${NC}       https://${LB_HOST}/health"
echo -e "${CYAN}----------------------------------------------------------------------"${NC}
echo -e "${BOLD}🔧 Jenkins Dashboard (Ingress):${NC} https://${LB_HOST}/jenkins"
echo -e "${BOLD}🔧 Jenkins Dashboard (Local):${NC}   kubectl port-forward svc/jenkins 18080:8080 -n devops"
echo -e "${BOLD}🔑 Jenkins Admin User:${NC}          admin"
echo -e "${BOLD}🔑 Jenkins Admin Password:${NC}      ${JENKINS_PASSWORD}"
echo -e "${CYAN}----------------------------------------------------------------------"${NC}
echo -e "${YELLOW}Note: Accept the browser SSL Self-Signed Certificate warning on first load.${NC}"
echo -e "${CYAN}======================================================================"${NC}