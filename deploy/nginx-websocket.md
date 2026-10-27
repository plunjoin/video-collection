# Nginx 配置示例 - 支持一起看 WebSocket

## 单域名部署 (推荐)

```nginx
server {
    listen 80;
    server_name video.example.com;
    client_max_body_size 25m;

    # 一起看 WebSocket 路径
    location /api/watch/ws {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;  # 24小时超时
    }

    # 其他API路径
    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 90s;
    }

    # 管理后台
    location /admin {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # RSS订阅
    location = /rss.xml {
        proxy_pass http://127.0.0.1:3000;
    }

    # 前台网站 (Astro)
    location / {
        proxy_pass http://127.0.0.1:4321;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## 分域名部署

### 管理后台域名
```nginx
server {
    listen 80;
    server_name admin.example.com;
    client_max_body_size 25m;

    # WebSocket
    location /api/watch/ws {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # 其他路径
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 90s;
    }
}
```

### 前台网站域名
```nginx
server {
    listen 80;
    server_name www.example.com;
    
    # WebSocket (如果前台也需要一起看功能)
    location /api/watch/ws {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # API路径
    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # RSS
    location = /rss.xml {
        proxy_pass http://127.0.0.1:3000;
    }

    # 前台页面
    location / {
        proxy_pass http://127.0.0.1:4321;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## HTTPS 配置 (使用 Certbot)

```bash
# 安装 Certbot
apt install certbot python3-certbot-nginx

# 自动配置 HTTPS
certbot --nginx -d video.example.com -d admin.example.com

# 重启 Nginx
systemctl restart nginx
```

Certbot 会自动添加以下配置:
```nginx
server {
    listen 443 ssl http2;
    server_name video.example.com;
    
    ssl_certificate /etc/letsencrypt/live/video.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/video.example.com/privkey.pem;
    
    # WebSocket 配置保持不变
    location /api/watch/ws {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        # ... 其他配置
    }
}
```

## WSS (WebSocket over TLS) 客户端连接

HTTPS 站点必须使用 WSS:

```javascript
// ✓ 正确
const ws = new WebSocket('wss://video.example.com/api/watch/ws?room_id=123');

// ✗ 错误 (HTTPS页面无法连接ws://)
const ws = new WebSocket('ws://video.example.com/api/watch/ws?room_id=123');
```

## 测试配置

### 测试 Nginx 配置
```bash
nginx -t
```

### 测试 WebSocket 连接
```bash
# 安装 wscat
npm install -g wscat

# 测试 ws:// (HTTP)
wscat -c "ws://localhost/api/watch/ws?room_id=1" \
  -H "Authorization: Bearer your_token_here"

# 测试 wss:// (HTTPS)
wscat -c "wss://video.example.com/api/watch/ws?room_id=1" \
  -H "Authorization: Bearer your_token_here"
```

## 常见问题

### 1. WebSocket 连接失败 (400 Bad Request)

**原因**: 缺少 Upgrade 头配置

**解决**:
```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

### 2. WebSocket 连接中断 (Connection closed)

**原因**: 超时时间太短

**解决**:
```nginx
proxy_read_timeout 86400;  # 24小时
```

### 3. HTTPS 页面无法连接 ws://

**原因**: 混合内容(Mixed Content)策略

**解决**: 使用 wss:// 或允许不安全内容(不推荐)

### 4. 401 Unauthorized

**原因**: Token 未传递或过期

**解决**: 确保 Authorization header 正确传递:
```nginx
proxy_set_header Authorization $http_authorization;
```

## 性能优化

### 连接复用
```nginx
upstream backend {
    server 127.0.0.1:3000;
    keepalive 32;
}

location / {
    proxy_pass http://backend;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
```

### 限流
```nginx
# 限制每个IP的WebSocket连接数
limit_conn_zone $binary_remote_addr zone=ws_conn:10m;

location /api/watch/ws {
    limit_conn ws_conn 10;  # 每IP最多10个连接
    # ... 其他配置
}
```

## 监控

### 检查活跃连接
```bash
# 查看当前WebSocket连接数
netstat -an | grep :3000 | grep ESTABLISHED | wc -l

# 查看Nginx状态
curl http://localhost/nginx_status
```

### Nginx 日志
```nginx
log_format ws_log '$remote_addr - $remote_user [$time_local] '
                  '"$request" $status $body_bytes_sent '
                  '"$http_upgrade" "$http_connection"';

access_log /var/log/nginx/ws_access.log ws_log;
```
