#!/usr/bin/env bash

installs=$(echo "$1" | tr "," "\n")
host=$2

install_node() {
  if [ -z "$(command -v node)" ]
  then
    curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -
    sudo apt-get install -y nodejs
  fi
}

install_nginx() {
  if [ -z "$(command -v nginx)" ]
  then
    sudo apt install curl gnupg2 ca-certificates lsb-release -y
    echo "deb http://nginx.org/packages/mainline/$(lsb_release -is | tr '[:upper:]' '[:lower:]') $(lsb_release -cs) nginx" \
      | sudo tee /etc/apt/sources.list.d/nginx.list
    curl -fsSL https://nginx.org/keys/nginx_signing.key | sudo apt-key add -
    sudo apt-get update && sudo apt-get install -y nginx
    echo "PATH=\"\$PATH:/usr/sbin\"" | sudo tee -a /etc/profile
  fi
}

install_redis() {
  if [ -z "$(command -v redis-cli)" ]
  then
    sudo apt install pwgen redis-server -y
    REDIS_PWD=$(pwgen 24 -1)
    echo "requirepass $REDIS_PWD" | sudo tee -a /etc/redis/redis.conf
    echo "bind 0.0.0.0" | sudo tee -a /etc/redis/redis.conf
    sudo systemctl restart redis
    gcloud compute project-info add-metadata --metadata "${HOSTNAME}_REDIS_PWD=$REDIS_PWD"
  fi
}


for ins in $installs;
do
  case $ins in
  node) install_node;;
  nginx) install_nginx;;
  redis) install_redis;;
  acme) install_acme;;
  esac
done

if [ ! -z "$host" ]; then
  CF_Email="$(gcloud compute project-info describe --flatten=commonInstanceMetadata.CF_Email --format=object)"
  CF_Key="$(gcloud compute project-info describe --flatten=commonInstanceMetadata.CF_Key --format=object)"
  if [ ! -z "$CF_Email" ] && [ ! -z "$CF_Key" ]; then
    echo "CF_Email=$CF_Email" | sudo tee -a /etc/envirement
    echo "CF_Key=$CF_Key" | sudo tee -a /etc/envirement
    install_node
    MY_ADDR=$(curl icanhazip.com);
    curl https://sh.open51.net/cf-dns.js | node - "$host" "$MY_ADDR" "$CF_Email" "$CF_Key"
    sleep 20
    if [ -z "$(command -v dig)" ]; then
      sudo apt-get install -y dnsutils
    fi
    ADDR=$(dig +short "$host" 1.1.1.1 | head -1)

    if [ "$MY_ADDR" == "$ADDR" ]; then
      sudo hostname "$host"
    fi
  fi
fi