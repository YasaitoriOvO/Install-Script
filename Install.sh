#!/bin/bash

set -e  # 如果发生错误则停止脚本

CONFIG_FILE="$(pwd)/YTR_CFG"

# 检查是否已有配置文件
if [ -f "$CONFIG_FILE" ]; then
    echo "检测到已有配置文件："
    cat "$CONFIG_FILE"
    read -p "是否使用现有配置文件? (y/n): " USE_EXISTING
    if [[ "$USE_EXISTING" == "y" || "$USE_EXISTING" == "Y" ]]; then
        source "$CONFIG_FILE"
    else
        echo "删除旧配置文件，重新配置..."
        rm "$CONFIG_FILE"
    fi
fi

# 如果没有配置文件，则重新输入配置
if [ ! -f "$CONFIG_FILE" ]; then
    read -p "请输入 MongoDB 数据库的名字 (MONGODB_NAME): " MONGODB_NAME
    read -p "请输入 MongoDB 数据库的用户名 (MONGODB_USERNAME): " MONGODB_USERNAME
    read -p "请输入 MongoDB 数据库的密码 (MONGODB_PASSWORD): " MONGODB_PASSWORD
    read -p "请输入 MongoDB 集群端口 (MONGODB_CLUSTER_PORT): " MONGODB_CLUSTER_PORT

    read -p "请输入 Elasticsearch 的端口: " ES_PORT
    read -p "请输入 Elasticsearch 管理员用户名: " ES_ADMIN_USERNAME
    read -p "请输入 Elasticsearch 管理员的密码: " ES_ADMIN_PASSWORD
    read -p "请输入 Elasticsearch Kibana 管理员用户名: " KIBANA_USERNAME
    read -p "请输入 Elasticsearch Kibana 管理员的密码: " KIBANA_PASSWORD

    # 保存配置到文件
    echo "保存配置到 $CONFIG_FILE..."
    cat <<EOL > "$CONFIG_FILE"
MONGODB_NAME="$MONGODB_NAME"
MONGODB_USERNAME="$MONGODB_USERNAME"
MONGODB_PASSWORD="$MONGODB_PASSWORD"
MONGODB_CLUSTER_PORT="$MONGODB_CLUSTER_PORT"
ES_PORT="$ES_PORT"
ES_ADMIN_USERNAME="$ES_ADMIN_USERNAME"
ES_ADMIN_PASSWORD="$ES_ADMIN_PASSWORD"
KIBANA_USERNAME="$KIBANA_USERNAME"
KIBANA_PASSWORD="$KIBANA_PASSWORD"
EOL
fi

echo "============================================="
echo "准备开始安装 MongoDB 和 Elasticsearch"
echo "============================================="

# 更新系统并安装必要的工具
echo "更新系统并安装必要的工具..."
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y wget curl gnupg openssl

# 安装 MongoDB
install_mongodb() {
    echo "安装 MongoDB..."
    wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    sudo apt-get update -y
    sudo apt-get install -y mongodb-org

    echo "配置 MongoDB 复制集..."
    sudo systemctl start mongod
    sudo systemctl enable mongod

    mongo <<EOF
rs.initiate()
use $MONGODB_NAME
db.createUser({user: "$MONGODB_USERNAME", pwd: "$MONGODB_PASSWORD", roles: [{role: "readWrite", db: "$MONGODB_NAME"}]})
EOF

    echo "MongoDB 已安装并配置完成。"
}

# 安装 Elasticsearch 和 Kibana
install_elasticsearch() {
    echo "安装 Elasticsearch..."
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
    echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
    sudo apt-get update -y
    sudo apt-get install -y elasticsearch kibana

    echo "生成自签名证书..."
    sudo mkdir -p /etc/elasticsearch/certs
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/elasticsearch/certs/elasticsearch.key \
        -out /etc/elasticsearch/certs/elasticsearch.crt \
        -subj "/CN=elasticsearch"

    echo "配置 Elasticsearch 使用 HTTPS..."
    sudo bash -c "cat >> /etc/elasticsearch/elasticsearch.yml <<EOL
xpack.security.enabled: true
xpack.security.http.ssl:
  enabled: true
  key: /etc/elasticsearch/certs/elasticsearch.key
  certificate: /etc/elasticsearch/certs/elasticsearch.crt
network.host: 0.0.0.0
http.port: $ES_PORT
EOL"

    sudo systemctl enable elasticsearch
    sudo systemctl start elasticsearch

    echo "配置 Kibana..."
    sudo bash -c "cat >> /etc/kibana/kibana.yml <<EOL
server.host: "0.0.0.0"
elasticsearch.hosts: ["https://localhost:$ES_PORT"]
elasticsearch.ssl:
  certificateAuthorities: ["/etc/elasticsearch/certs/elasticsearch.crt"]
EOL"

    sudo systemctl enable kibana
    sudo systemctl start kibana

    echo "设置 Elasticsearch 管理员和 Kibana 用户..."
    curl -k -X POST "https://localhost:$ES_PORT/_security/user/$ES_ADMIN_USERNAME" -H 'Content-Type: application/json' -u "elastic:changeme" -d '{
      "password": "$ES_ADMIN_PASSWORD",
      "roles": ["superuser"],
      "full_name": "Elasticsearch Admin"
    }'

    curl -k -X POST "https://localhost:$ES_PORT/_security/user/$KIBANA_USERNAME" -H 'Content-Type: application/json' -u "elastic:changeme" -d '{
      "password": "$KIBANA_PASSWORD",
      "roles": ["kibana_admin"],
      "full_name": "Kibana Admin"
    }'

    echo "Elasticsearch 和 Kibana 已安装并配置完成。"
}

# 捕获错误并打印
trap 'echo "安装过程中发生错误，请检查输出日志。"; exit 1' ERR

# 执行安装
install_mongodb
install_elasticsearch

# 输出配置信息到 /DONE.txt
echo "MongoDB 和 Elasticsearch 部署完成！" > /DONE.txt
echo "MongoDB Name: $MONGODB_NAME" >> /DONE.txt
echo "MongoDB Username: $MONGODB_USERNAME" >> /DONE.txt
echo "MongoDB Password: $MONGODB_PASSWORD" >> /DONE.txt
echo "MongoDB Cluster Port: $MONGODB_CLUSTER_PORT" >> /DONE.txt

echo "Elasticsearch Port: $ES_PORT" >> /DONE.txt
echo "Elasticsearch Admin Username: $ES_ADMIN_USERNAME" >> /DONE.txt
echo "Elasticsearch Admin Password: $ES_ADMIN_PASSWORD" >> /DONE.txt
echo "Kibana Admin Username: $KIBANA_USERNAME" >> /DONE.txt
echo "Kibana Admin Password: $KIBANA_PASSWORD" >> /DONE.txt

# 打印完成信息
echo "============================================="
echo "安装完成！配置已保存到 /DONE.txt"
echo "============================================="
