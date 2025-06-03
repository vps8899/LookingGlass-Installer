#!/bin/bash

set -e

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 用户运行此脚本。"
  exit 1
fi

# 获取公网 IPv4
SERVER_IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me || curl -s ipinfo.io/ip)
if [ -z "$SERVER_IP" ]; then
  echo "无法获取公网 IP，请检查网络。"
  exit 1
fi

# 获取域名
read -p "请输入你解析好的域名（如 lg.example.com）: " DOMAIN

echo "==> 安装基础组件..."
apt update
apt install -y nginx php php-fpm php-cli php-curl php-mbstring php-common git unzip mtr-tiny traceroute dnsutils whois curl sudo

echo "==> 安装 Certbot..."
apt install -y certbot python3-certbot-nginx

echo "==> 克隆 Looking Glass..."
cd /var/www/
git clone https://github.com/Franzip/LookingGlass.git looking-glass
cd looking-glass

echo "==> 写入配置文件 config.php..."
cat > config.php <<EOF
<?php
\$site_title = 'CLAW VPS Looking Glass';

\$servers = array(
    'claw' => array(
        'name' => 'CLAW VPS 节点',
        'ip' => '$SERVER_IP',
        'location' => 'Auto Detected',
        'test_ipv4' => '$SERVER_IP',
    ),
);
?>
EOF

chown -R www-data:www-data /var/www/looking-glass

echo "==> 配置 Nginx..."
cat > /etc/nginx/sites-available/looking-glass <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/looking-glass;
    index index.php;

    access_log /var/log/nginx/lg_access.log;
    error_log /var/log/nginx/lg_error.log;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/looking-glass /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

echo "==> 配置 sudoers 权限..."
cat > /etc/sudoers.d/lg-commands <<EOF
www-data ALL=(ALL) NOPASSWD: /usr/bin/mtr, /usr/bin/traceroute, /usr/bin/whois, /usr/bin/dig, /bin/ping
EOF
chmod 440 /etc/sudoers.d/lg-commands

echo "==> 获取 HTTPS 证书..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

echo
echo "✅ Looking Glass 安装并启用 HTTPS 成功！"
echo "🌐 请访问：https://$DOMAIN"
echo "📁 网站目录：/var/www/looking-glass"
echo "⚙️ 配置文件：/var/www/looking-glass/config.php"
