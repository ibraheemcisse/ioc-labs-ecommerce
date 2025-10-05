#!/bin/bash
set -e

# Variables
CLUSTER_NAME="ioc-labs-cluster"
SERVICE_NAME="ioc-labs-backend-service"
TASK_FAMILY="ioc-labs-backend-task"
REGION="us-east-1"
IMAGE="570220934078.dkr.ecr.us-east-1.amazonaws.com/ioc-labs-backend:latest"

# Create ECS cluster
aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $REGION

echo "ECS cluster created"
