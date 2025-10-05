#!/bin/bash
set -e

CLUSTER_NAME="ioc-labs-cluster"
SERVICE_NAME="ioc-labs-backend-service"
TASK_FAMILY="ioc-labs-backend-task"
REGION="us-east-1"
IMAGE="570220934078.dkr.ecr.us-east-1.amazonaws.com/ioc-labs-backend:latest"

# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text | tr '\t' ',')

# Create security group for ALB
ALB_SG=$(aws ec2 create-security-group \
  --group-name ioc-labs-alb-sg \
  --description "ALB security group" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# Create security group for ECS tasks
ECS_SG=$(aws ec2 create-security-group \
  --group-name ioc-labs-ecs-sg \
  --description "ECS tasks security group" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $ECS_SG \
  --protocol tcp \
  --port 8080 \
  --source-group $ALB_SG

# Allow ECS to reach RDS (using existing RDS security group)
RDS_SG="sg-03759d36b1cc20666"
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $ECS_SG 2>/dev/null || echo "RDS rule already exists"

# Create ALB
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name ioc-labs-alb-fargate \
  --subnets $(echo $SUBNETS | tr ',' ' ') \
  --security-groups $ALB_SG \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Create target group
TG_ARN=$(aws elbv2 create-target-group \
  --name ioc-labs-tg-fargate \
  --protocol HTTP \
  --port 8080 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-path /api/products \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# Create listener
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN

# Create IAM role for ECS task execution
ROLE_NAME="ecsTaskExecutionRole-ioc"
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' 2>/dev/null || echo "Role already exists"

aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)

# Register task definition
aws ecs register-task-definition \
  --family $TASK_FAMILY \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 512 \
  --memory 1024 \
  --execution-role-arn $ROLE_ARN \
  --container-definitions "[
    {
      \"name\": \"backend\",
      \"image\": \"$IMAGE\",
      \"portMappings\": [{\"containerPort\": 8080, \"protocol\": \"tcp\"}],
      \"environment\": [
        {\"name\": \"DATABASE_URL\", \"value\": \"postgres://iocadmin:SecurePass123Change!@ioc-labs-db.c85gyeucovob.us-east-1.rds.amazonaws.com:5432/ioc_labs_prod?sslmode=disable\"},
        {\"name\": \"REDIS_URL\", \"value\": \"ioc-labs-redis.vaj0gw.0001.use1.cache.amazonaws.com:6379\"},
        {\"name\": \"PORT\", \"value\": \"8080\"},
        {\"name\": \"STRIPE_SECRET_KEY\", \"value\": \"${STRIPE_SECRET_KEY}"},
        {\"name\": \"STRIPE_WEBHOOK_SECRET\", \"value\": \"${STRIPE_WEBHOOK_SECRET}"}
      ],
      \"logConfiguration\": {
        \"logDriver\": \"awslogs\",
        \"options\": {
          \"awslogs-group\": \"/ecs/ioc-labs-backend\",
          \"awslogs-region\": \"$REGION\",
          \"awslogs-stream-prefix\": \"ecs\",
          \"awslogs-create-group\": \"true\"
        }
      }
    }
  ]"

# Create ECS service
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --task-definition $TASK_FAMILY \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$ECS_SG],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=$TG_ARN,containerName=backend,containerPort=8080"

# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --query 'LoadBalancers[0].DNSName' --output text)

echo ""
echo "Deployment complete!"
echo "ALB URL: http://$ALB_DNS"
echo "Test: curl http://$ALB_DNS/api/products"
