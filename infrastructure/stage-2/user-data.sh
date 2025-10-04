#!/bin/bash
apt update && apt install -y golang-go git

cd /home/ubuntu
git clone https://github.com/ibraheemcisse/ioc-labs-ecommerce.git
cd ioc-labs-ecommerce

/usr/bin/go build -o ioc-labs-server cmd/api/main.go

cat > .env << ENV
PORT=8080
DATABASE_HOST=ioc-labs-db.c85gyeucovob.us-east-1.rds.amazonaws.com
DATABASE_NAME=ioc_labs_prod
DATABASE_USER=iocadmin
DATABASE_PASSWORD=SecurePass123Change!
REDIS_HOST=ioc-labs-redis.em66cw.0001.use1.cache.amazonaws.com
REDIS_PORT=6379
JWT_SECRET=$(openssl rand -base64 32)
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
