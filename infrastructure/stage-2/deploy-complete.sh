#!/bin/bash
set -e

REGION="us-east-1"
KEY_NAME="ioc-labs-key"
SG_ID="sg-03759d36b1cc20666"

echo "1/5 Creating RDS PostgreSQL..."
aws rds create-db-instance \
  --db-instance-identifier ioc-labs-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 14.13 \
  --master-username iocadmin \
  --master-user-password "SecurePass123Change!" \
  --allocated-storage 20 \
  --vpc-security-group-ids $SG_ID \
  --publicly-accessible \
  --backup-retention-period 7 \
  --region $REGION

echo "Waiting for RDS (this takes 5-10 minutes)..."
aws rds wait db-instance-available \
  --db-instance-identifier ioc-labs-db \
  --region $REGION

DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier ioc-labs-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text \
  --region $REGION)

echo "RDS Ready: $DB_ENDPOINT"

echo "2/5 Creating ElastiCache Redis..."
aws elasticache create-cache-cluster \
  --cache-cluster-id ioc-labs-redis \
  --engine redis \
  --cache-node-type cache.t3.micro \
  --num-cache-nodes 1 \
  --security-group-ids $SG_ID \
  --region $REGION

aws elasticache wait cache-cluster-available \
  --cache-cluster-id ioc-labs-redis \
  --region $REGION

REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters \
  --cache-cluster-id ioc-labs-redis \
  --show-cache-node-info \
  --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
  --output text \
  --region $REGION)

echo "Redis Ready: $REDIS_ENDPOINT"

echo "3/5 Setting up database..."
PGPASSWORD="SecurePass123Change!" psql -h $DB_ENDPOINT -U iocadmin -d postgres << SQL
CREATE DATABASE ioc_labs_prod;
\c ioc_labs_prod
$(cat ../../migrations/*.sql)
SQL

echo "4/5 Creating Application Load Balancer..."
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text \
  --region $REGION)

SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=default-for-az,Values=true" \
  --query 'Subnets[*].SubnetId' \
  --output text \
  --region $REGION)

TG_ARN=$(aws elbv2 create-target-group \
  --name ioc-labs-tg \
  --protocol HTTP \
  --port 8080 \
  --vpc-id $VPC_ID \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --region $REGION \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

LB_ARN=$(aws elbv2 create-load-balancer \
  --name ioc-labs-alb \
  --subnets $SUBNETS \
  --security-groups $SG_ID \
  --region $REGION \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

aws elbv2 create-listener \
  --load-balancer-arn $LB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN \
  --region $REGION

LB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $LB_ARN \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region $REGION)

echo "ALB Ready: $LB_DNS"

echo "5/5 Launching 2 EC2 instances..."

# Create user data with actual endpoints
cat > user-data-final.sh << USERDATA
#!/bin/bash
apt update && apt install -y golang-go git postgresql-client

cd /home/ubuntu
git clone https://github.com/ibraheemcisse/ioc-labs-ecommerce.git
cd ioc-labs-ecommerce

go build -o ioc-labs-server cmd/api/main.go

cat > .env << ENV
PORT=8080
DATABASE_HOST=$DB_ENDPOINT
DATABASE_NAME=ioc_labs_prod
DATABASE_USER=iocadmin
DATABASE_PASSWORD=SecurePass123Change!
REDIS_HOST=$REDIS_ENDPOINT
REDIS_PORT=6379
JWT_SECRET=\$(openssl rand -base64 32)
ENV

cat > /etc/systemd/system/ioc-labs.service << SERVICE
[Unit]
Description=IOC Labs API
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/ioc-labs-ecommerce
EnvironmentFile=/home/ubuntu/ioc-labs-ecommerce/.env
ExecStart=/home/ubuntu/ioc-labs-ecommerce/ioc-labs-server
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable ioc-labs
systemctl start ioc-labs
USERDATA

AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text \
  --region $REGION)

for i in 1 2; do
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t2.small \
    --key-name $KEY_NAME \
    --security-group-ids $SG_ID \
    --user-data file://user-data-final.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ioc-labs-app-$i}]" \
    --region $REGION \
    --query 'Instances[0].InstanceId' \
    --output text)
  
  echo "Instance $i: $INSTANCE_ID"
  
  aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION
  
  aws elbv2 register-targets \
    --target-group-arn $TG_ARN \
    --targets Id=$INSTANCE_ID \
    --region $REGION
done

echo ""
echo "DEPLOYMENT COMPLETE"
echo "=================="
echo "Load Balancer: http://$LB_DNS"
echo "RDS: $DB_ENDPOINT"
echo "Redis: $REDIS_ENDPOINT"
echo ""
echo "Wait 3-5 minutes for instances to initialize, then test:"
echo "  curl http://$LB_DNS/health"
echo "  curl http://$LB_DNS/api/products"
echo ""
echo "Monthly Cost: ~\$85"
