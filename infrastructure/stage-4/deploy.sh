#!/bin/bash
set -e

# Stage 4: Single-node K8s with Meshery/Kanvas for IOC-Labs
# Instance: t3.large (2 vCPU, 8GB RAM)
# Cost: ~$60/month + existing RDS/Redis

echo "=== Stage 4: Kubernetes + Meshery/Kanvas Deployment ==="
echo "This will create a single-node K8s cluster with Meshery for visual design"
echo ""

# Configuration
INSTANCE_TYPE="t3.large"
AMI_ID="ami-0c7217cdde317cfec"  
KEY_NAME="ioc-labs-k8s-key"    
REGION="us-east-1"
CLUSTER_NAME="ioc-labs-k8s"

# Database connection info (from Stage 3)
RDS_HOST="ioc-labs-db.c85gyeucovob.us-east-1.rds.amazonaws.com"
REDIS_HOST="ioc-labs-redis.vaj0gw.0001.use1.cache.amazonaws.com"
ECR_IMAGE="570220934078.dkr.ecr.us-east-1.amazonaws.com/ioc-labs-backend:latest"

echo "Creating security group..."
SG_ID=$(aws ec2 create-security-group \
  --group-name ioc-labs-k8s-sg \
  --description "Security group for IOC-Labs K8s cluster" \
  --region $REGION \
  --query 'GroupId' \
  --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters Name=group-name,Values=ioc-labs-k8s-sg \
    --region $REGION \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

echo "Security Group ID: $SG_ID"

# Configure security group rules
echo "Configuring security group rules..."
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 2>/dev/null || true  # SSH
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 2>/dev/null || true  # HTTP
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0 2>/dev/null || true  # HTTPS
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 9081 --cidr 0.0.0.0/0 2>/dev/null || true  # Meshery UI
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 6443 --cidr 0.0.0.0/0 2>/dev/null || true  # K8s API
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 8080 --cidr 0.0.0.0/0 2>/dev/null || true  # App

echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$CLUSTER_NAME},{Key=Stage,Value=4},{Key=Purpose,Value=Meshery-Kanvas}]" \
  --region $REGION \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"
echo "Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "Public IP: $PUBLIC_IP"
echo "Waiting 30 seconds for SSH to be ready..."
sleep 30

# Create setup script to run on the instance
cat > /tmp/k8s-setup.sh << 'SETUP_SCRIPT'
#!/bin/bash
set -e

echo "=== Installing K3s (Lightweight Kubernetes) ==="
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

# Wait for k3s to be ready
echo "Waiting for K3s to be ready..."
sleep 10
kubectl wait --for=condition=Ready nodes --all --timeout=60s

echo "=== K3s Installation Complete ==="
kubectl get nodes

echo "=== Installing Meshery ==="
# Install mesheryctl
curl -L https://meshery.io/install | ADAPTERS=istio bash -

# Start Meshery
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mesheryctl system start --skip-browser

echo "=== Meshery Installation Complete ==="
sleep 10

# Get Meshery status
mesheryctl system status

echo "=== Setup Complete ==="
echo "K3s is running"
echo "Meshery is running"
echo ""
echo "Access points:"
echo "  Meshery UI: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9081"
echo "  Kanvas: Click 'Kanvas' in Meshery UI"
echo ""
SETUP_SCRIPT

# Copy and execute setup script
echo "Copying setup script to instance..."
scp -o StrictHostKeyChecking=no -i ~/.ssh/${KEY_NAME}.pem /tmp/k8s-setup.sh ubuntu@${PUBLIC_IP}:/tmp/

echo "Running K3s and Meshery installation (this takes ~5 minutes)..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/${KEY_NAME}.pem ubuntu@${PUBLIC_IP} 'sudo bash /tmp/k8s-setup.sh'

echo ""
echo "=== Creating Kubernetes Manifests for IOC-Labs Backend ==="

# Create K8s manifests locally
mkdir -p infrastructure/stage-4-k8s

cat > infrastructure/stage-4-k8s/ioc-labs-deployment.yaml << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ioc-labs
---
apiVersion: v1
kind: Secret
metadata:
  name: ioc-labs-secrets
  namespace: ioc-labs
type: Opaque
stringData:
  DB_HOST: "${RDS_HOST}"
  DB_PORT: "5432"
  DB_NAME: "ioclabs"
  DB_USER: "ioclabs"
  DB_PASSWORD: "your-db-password"  # CHANGE THIS
  REDIS_HOST: "${REDIS_HOST}"
  REDIS_PORT: "6379"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ioc-labs-backend
  namespace: ioc-labs
  labels:
    app: ioc-labs-backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ioc-labs-backend
  template:
    metadata:
      labels:
        app: ioc-labs-backend
        version: v1
    spec:
      containers:
      - name: backend
        image: ${ECR_IMAGE}
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        env:
        - name: PORT
          value: "8080"
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: ioc-labs-secrets
              key: DB_HOST
        - name: DB_PORT
          valueFrom:
            secretKeyRef:
              name: ioc-labs-secrets
              key: DB_PORT
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: ioc-labs-secrets
              key: DB_NAME
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: ioc-labs-secrets
              key: DB_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ioc-labs-secrets
              key: DB_PASSWORD
        - name: REDIS_HOST
          valueFrom:
            secretKeyRef:
              name: ioc-labs-secrets
              key: REDIS_HOST
        - name: REDIS_PORT
          valueFrom:
            secretKeyRef:
              name: ioc-labs-secrets
              key: REDIS_PORT
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1024Mi
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: ioc-labs-backend
  namespace: ioc-labs
  labels:
    app: ioc-labs-backend
spec:
  type: LoadBalancer
  selector:
    app: ioc-labs-backend
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
    name: http
EOF

echo "Kubernetes manifests created in infrastructure/stage-4-k8s/"

echo ""
echo "=== Configuring AWS ECR Access ==="

# Create ECR credentials for K8s
echo "Creating ECR pull secret..."
ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${PUBLIC_IP} << 'REMOTE_ECR'
# Install AWS CLI
sudo apt-get update -qq
sudo apt-get install -y awscli

# Get ECR login token
aws ecr get-login-password --region us-east-1 > /tmp/ecr-token

# Create K8s secret for ECR
kubectl create namespace ioc-labs --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret docker-registry ecr-secret \
  --docker-server=570220934078.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(cat /tmp/ecr-token) \
  --namespace=ioc-labs \
  --dry-run=client -o yaml | kubectl apply -f -

# Patch default service account to use the secret
kubectl patch serviceaccount default \
  -n ioc-labs \
  -p '{"imagePullSecrets": [{"name": "ecr-secret"}]}'

rm /tmp/ecr-token
REMOTE_ECR

echo ""
echo "=== Deploying IOC-Labs Backend to Kubernetes ==="

# Copy manifests to instance
scp -i ~/.ssh/${KEY_NAME}.pem infrastructure/stage-4-k8s/ioc-labs-deployment.yaml ubuntu@${PUBLIC_IP}:/tmp/

# Deploy application
ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${PUBLIC_IP} << 'REMOTE_DEPLOY'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Deploying application..."
sudo kubectl apply -f /tmp/ioc-labs-deployment.yaml

echo "Waiting for deployment to be ready..."
sudo kubectl wait --for=condition=available --timeout=120s deployment/ioc-labs-backend -n ioc-labs || true

echo ""
echo "=== Deployment Status ==="
sudo kubectl get all -n ioc-labs

echo ""
echo "=== Pod Details ==="
sudo kubectl describe pods -n ioc-labs | grep -A 5 "Events:"
REMOTE_DEPLOY

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          Stage 4 Deployment Complete! 🎉                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Instance Details:"
echo "  Instance ID: $INSTANCE_ID"
echo "  Public IP: $PUBLIC_IP"
echo "  Instance Type: $INSTANCE_TYPE"
echo ""
echo "Access Points:"
echo "  🎨 Meshery/Kanvas UI: http://${PUBLIC_IP}:9081"
echo "  🚀 IOC-Labs Backend:  http://${PUBLIC_IP}:80"
echo "  🔧 SSH Access:        ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${PUBLIC_IP}"
echo ""
echo "Kubernetes Info:"
echo "  Cluster: k3s (single-node)"
echo "  Namespace: ioc-labs"
echo "  Replicas: 2 pods"
echo "  Service Type: LoadBalancer"
echo ""
echo "Next Steps:"
echo "  1. Open Meshery UI and complete initial setup"
echo "  2. Navigate to 'Kanvas' in Meshery"
echo "  3. Connect to your K8s cluster (should auto-detect)"
echo "  4. Click 'Import' to visualize your running deployment"
echo "  5. See your IOC-Labs backend in visual topology!"
echo ""
echo "Useful Commands (run these on the instance):"
echo "  # View all resources"
echo "  kubectl get all -n ioc-labs"
echo ""
echo "  # View logs"
echo "  kubectl logs -f deployment/ioc-labs-backend -n ioc-labs"
echo ""
echo "  # Access Meshery CLI"
echo "  mesheryctl system status"
echo ""
echo "  # Port forward to access app locally"
echo "  kubectl port-forward svc/ioc-labs-backend 8080:80 -n ioc-labs"
echo ""
echo "Cost Estimate:"
echo "  EC2 t3.large:     ~\$60/month"
echo "  RDS (existing):   ~\$32/month"
echo "  Redis (existing): ~\$15/month"
echo "  Total:            ~\$107/month"
echo ""
echo "To tear down Stage 4:"
echo "  aws ec2 terminate-instances --instance-ids $INSTANCE_ID"
echo ""
