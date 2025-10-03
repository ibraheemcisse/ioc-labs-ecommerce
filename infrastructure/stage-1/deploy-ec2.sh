#!/bin/bash
# IOC Labs - Complete EC2 Deployment Script
# Run from your local machine (WSL)

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   IOC Labs - EC2 Deployment (Stage 1)         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Configuration
AWS_REGION="us-east-1"
INSTANCE_TYPE="t2.small"  # t2.micro is too small for production
KEY_NAME="ioc-labs-key"
SECURITY_GROUP_NAME="ioc-labs-sg"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Region: $AWS_REGION"
echo "  Instance Type: $INSTANCE_TYPE"
echo "  Key Name: $KEY_NAME"
echo ""

read -p "Continue with these settings? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# ============================================================================
# Step 1: Create Key Pair
# ============================================================================
echo -e "${YELLOW}Creating SSH key pair...${NC}"

if [ -f "$KEY_NAME.pem" ]; then
    echo "Key pair already exists locally"
else
    aws ec2 create-key-pair \
        --key-name $KEY_NAME \
        --query 'KeyMaterial' \
        --output text \
        --region $AWS_REGION > $KEY_NAME.pem
    
    chmod 400 $KEY_NAME.pem
    echo -e "${GREEN}✓ Key pair created: $KEY_NAME.pem${NC}"
fi

# ============================================================================
# Step 2: Create Security Group
# ============================================================================
echo -e "${YELLOW}Creating security group...${NC}"

# Check if security group exists
SG_ID=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values=$SECURITY_GROUP_NAME \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region $AWS_REGION 2>/dev/null || echo "None")

if [ "$SG_ID" == "None" ]; then
    SG_ID=$(aws ec2 create-security-group \
        --group-name $SECURITY_GROUP_NAME \
        --description "IOC Labs E-Commerce Security Group" \
        --region $AWS_REGION \
        --query 'GroupId' \
        --output text)
    
    echo -e "${GREEN}✓ Security group created: $SG_ID${NC}"
    
    # Add rules
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --region $AWS_REGION
    
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --region $AWS_REGION
    
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --region $AWS_REGION
    
    echo -e "${GREEN}✓ Security group rules added${NC}"
else
    echo "Security group already exists: $SG_ID"
fi

# ============================================================================
# Step 3: Launch EC2 Instance
# ============================================================================
echo -e "${YELLOW}Launching EC2 instance...${NC}"

# Get latest Ubuntu 22.04 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text \
    --region $AWS_REGION)

echo "Using AMI: $AMI_ID"

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SG_ID \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ioc-labs-stage1}]' \
    --region $AWS_REGION \
    --query 'Instances[0].InstanceId' \
    --output text)

echo -e "${GREEN}✓ Instance launched: $INSTANCE_ID${NC}"
echo "Waiting for instance to be running..."

aws ec2 wait instance-running \
    --instance-ids $INSTANCE_ID \
    --region $AWS_REGION

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text \
    --region $AWS_REGION)

echo -e "${GREEN}✓ Instance running at: $PUBLIC_IP${NC}"

# Wait for SSH to be ready
echo "Waiting for SSH to be available (this may take 1-2 minutes)..."
sleep 30

MAX_RETRIES=20
RETRY_COUNT=0
while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i $KEY_NAME.pem ubuntu@$PUBLIC_IP "echo 'SSH ready'" 2>/dev/null; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo -e "${RED}Failed to connect via SSH${NC}"
        exit 1
    fi
    echo "Retry $RETRY_COUNT/$MAX_RETRIES..."
    sleep 10
done

echo -e "${GREEN}✓ SSH connection established${NC}"

# ============================================================================
# Step 4: Prepare Deployment Files
# ============================================================================
echo -e "${YELLOW}Building application...${NC}"

cd ~/omega/ioc-labs-ecommerce

# Build Go binary for Linux
GOOS=linux GOARCH=amd64 go build -o ioc-labs-server cmd/api/main.go
echo -e "${GREEN}✓ Binary built${NC}"

# Create deployment package
mkdir -p deploy-temp
cp ioc-labs-server deploy-temp/
cp -r frontend deploy-temp/
cp -r migrations deploy-temp/
cp .env.example deploy-temp/.env

# Update .env with production settings
cat > deploy-temp/.env << 'ENVFILE'
PORT=8080
ENVIRONMENT=production

DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_USER=ioc_user
DATABASE_PASSWORD=SecurePassword123!
DATABASE_NAME=ioc_labs_prod
DATABASE_SSLMODE=disable

REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=

JWT_SECRET=$(openssl rand -base64 32)
JWT_EXPIRY_HOURS=24

APP_NAME=IOC_Labs_E-Commerce
APP_VERSION=1.0.0
ALLOWED_ORIGINS=*
ENVFILE

echo -e "${GREEN}✓ Deployment package prepared${NC}"

# ============================================================================
# Step 5: Copy Files to EC2
# ============================================================================
echo -e "${YELLOW}Copying files to EC2...${NC}"

scp -o StrictHostKeyChecking=no -i $KEY_NAME.pem -r deploy-temp/* ubuntu@$PUBLIC_IP:~/

echo -e "${GREEN}✓ Files copied${NC}"

# Clean up local deployment files
rm -rf deploy-temp
rm ioc-labs-server

# ============================================================================
# Step 6: Setup EC2 Environment
# ============================================================================
echo -e "${YELLOW}Setting up EC2 environment...${NC}"

ssh -o StrictHostKeyChecking=no -i $KEY_NAME.pem ubuntu@$PUBLIC_IP << 'ENDSSH'
set -e

echo "Updating system..."
sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y

echo "Installing PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib

echo "Installing Redis..."
sudo apt install -y redis-server

echo "Installing Nginx..."
sudo apt install -y nginx

echo "Configuring PostgreSQL..."
sudo -u postgres psql << PSQL
CREATE DATABASE ioc_labs_prod;
CREATE USER ioc_user WITH PASSWORD 'SecurePassword123!';
GRANT ALL PRIVILEGES ON DATABASE ioc_labs_prod TO ioc_user;
ALTER DATABASE ioc_labs_prod OWNER TO ioc_user;
\q
PSQL

# Allow password authentication for ioc_user
sudo sed -i 's/peer/md5/g' /etc/postgresql/*/main/pg_hba.conf
sudo systemctl restart postgresql

echo "Running database migrations..."
export PGPASSWORD='SecurePassword123!'
for migration in ~/migrations/*.sql; do
    psql -h localhost -U ioc_user -d ioc_labs_prod -f "$migration"
done

echo "Creating systemd service..."
sudo tee /etc/systemd/system/ioc-labs.service << SERVICE
[Unit]
Description=IOC Labs E-Commerce API
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu
EnvironmentFile=/home/ubuntu/.env
ExecStart=/home/ubuntu/ioc-labs-server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

echo "Configuring Nginx..."
sudo tee /etc/nginx/sites-available/ioc-labs << 'NGINX'
server {
    listen 80;
    server_name _;

    client_max_body_size 10M;

    # Frontend
    location / {
        root /home/ubuntu/frontend;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    # API endpoints
    location /api/ {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Health check
    location /health {
        proxy_pass http://localhost:8080/health;
        access_log off;
    }
}
NGINX

sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/ioc-labs /etc/nginx/sites-enabled/
sudo nginx -t

echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable ioc-labs
sudo systemctl start ioc-labs
sudo systemctl restart nginx

echo "Configuring firewall..."
sudo ufw --force enable
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

echo "✓ EC2 setup complete!"
ENDSSH

echo -e "${GREEN}✓ EC2 environment configured${NC}"

# ============================================================================
# Step 7: Verify Deployment
# ============================================================================
echo ""
echo -e "${YELLOW}Verifying deployment...${NC}"
sleep 5

# Test health endpoint
if curl -f http://$PUBLIC_IP/health 2>/dev/null; then
    echo -e "${GREEN}✓ Health check passed${NC}"
else
    echo -e "${RED}✗ Health check failed${NC}"
fi

# Test API
if curl -f http://$PUBLIC_IP/api/products 2>/dev/null; then
    echo -e "${GREEN}✓ API responding${NC}"
else
    echo -e "${YELLOW}⚠ API test failed (might need data)${NC}"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Deployment Complete!                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Instance Details:${NC}"
echo "  Instance ID: $INSTANCE_ID"
echo "  Public IP: $PUBLIC_IP"
echo "  SSH Command: ssh -i $KEY_NAME.pem ubuntu@$PUBLIC_IP"
echo ""
echo -e "${BLUE}Access Your Application:${NC}"
echo "  Website: http://$PUBLIC_IP"
echo "  API: http://$PUBLIC_IP/api/products"
echo "  Health: http://$PUBLIC_IP/health"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  Check logs: ssh -i $KEY_NAME.pem ubuntu@$PUBLIC_IP 'sudo journalctl -u ioc-labs -f'"
echo "  Restart API: ssh -i $KEY_NAME.pem ubuntu@$PUBLIC_IP 'sudo systemctl restart ioc-labs'"
echo "  Check status: ssh -i $KEY_NAME.pem ubuntu@$PUBLIC_IP 'sudo systemctl status ioc-labs'"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Visit http://$PUBLIC_IP in your browser"
echo "  2. Register a user account"
echo "  3. Test the shopping flow"
echo "  4. (Optional) Setup a domain name"
echo "  5. (Optional) Setup SSL with Let's Encrypt"
echo ""
echo -e "${YELLOW}Save these files:${NC}"
echo "  - $KEY_NAME.pem (SSH key - keep it safe!)"
echo "  - Instance ID: $INSTANCE_ID"
echo "  - Public IP: $PUBLIC_IP"
echo ""
