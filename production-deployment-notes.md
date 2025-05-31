# Deployment notes

These are some notes to remind myself how I deployed the application mostly within the AWS free tier via docker compose. I went beyond the free tier to register alex-bogl.com, but this isn't necessary.

Eventually, I'd like to automate the process and perhaps try out a more AWS-native approach with EKS.

The steps are:

1. Set up an EC2 instance
2. Register a domain name via Route 53
3. Point the domain name to the EC2 public IP 
4. Register a TLS certificate with certbot
5. Set up docker on the instance
6. Deploy bogl via docker swarm
7. Set up certificate renewal with a certbot cron job


# Launch EC2 Instance:

Go to AWS Console > EC2 > Launch Instance

Choose Ubuntu Server 22.04 LTS (free tier eligible)

Select t2.micro instance type (free tier)

Create or select a key pair for SSH access and store this locally at ~/.ssh

Configure security group:

 * SSH (port 22) from your IP
 * HTTP (port 80) from anywhere (0.0.0.0/0)
 * HTTPS (port 443) from anywhere (0.0.0.0/0)

# SSH and update the instance

chmod 400 ~/.ssh/alex-bogl-docker-compose.pem

ssh -i ~/.ssh/alex-bogl-docker-compose.pem ubuntu@3.142.136.151

sudo apt update && sudo apt upgrade -y

Reboot via AWS console for kernel upgrade to take effect.

# Register a domain name

AWS Console > Route 53 > Register domain > alex-bogl.com > Select > Proceed to checkout

# Update DNS records

Go to Route 53 > Hosted Zones > alex-bogl.com
Create A records pointing to EC2 instance:

Record 1:

Name: alex-bogl.com
Type: A
Value: EC2 instance public IP address
TTL: 300


Record 2:

Name: www.alex-bogl.com
Type: A
Value: EC2 instance public IP address
TTL: 300

Wait for DNS propagation (test with `nslookup alex-bogl.com`)

# SSL setup

## Run certbot in the EC2 instance

sudo apt install -y certbot

sudo certbot certonly --standalone \
    -d alex-bogl.com \
    -d www.alex-bogl.com \
    --email alexgrejuc@gmail.com \
    --agree-tos \
    --no-eff-email

# Set up docker in the EC2 instance

## Install Docker

```
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
```

```
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

```
sudo apt update
```

```
sudo apt install -y docker-ce docker-ce-cli containerd.io
```


## Create docker group
sudo groupadd docker
sudo usermod -aG docker ubuntu

## Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

## Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

## Log out and back in for group changes to take effect

exit

# Build and push the docker images

Can be done wherever, but I did it on my laptop. I used docker buildx for multi-architecture builds since I'm building it on apple silicon but deploying to an arm64 device.

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t alexgrejuc/bogl \
  --push /Users/alexgrejuc/Dev/alex-bogl/bogl-interpreter

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t alexgrejuc/bogl-editor \
  --push /Users/alexgrejuc/Dev/alex-bogl/bogl-editor

# Clone the bogl-deploy repo on the EC2 instance at /home/ubuntu/bogl-deploy
git clone https://github.com/alex-bogl/bogl-deploy.git

# Run app with docker compose
docker-compose -f bogl-deploy/docker-compose.production.yml pull
docker-compose -f bogl-deploy/docker-compose.production.yml up -d

# Set up cron job for cert renewal
sudo crontab -e

0 0,12 * * * /usr/bin/certbot renew --quiet --pre-hook "docker-compose -f /home/ubuntu/bogl-deploy/docker-compose.production.yml stop bogl-editor" --post-hook "docker-compose -f /home/ubuntu/bogl-deploy/docker-compose.production.yml start bogl-editor"
