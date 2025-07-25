#!/bin/bash
# RTPI-PEN System Initialization Script
# Comprehensive system setup before any services start

set -e

echo "🏥 Starting RTPI-PEN System Initialization..."

# Create required directories
create_base_directories() {
    local base_dirs=(
        "/opt/kasm"
        "/opt/empire"
        "/opt/empire/data"
        "/opt/rtpi-orchestrator"
        "/opt/rtpi-orchestrator/data"
        "/opt/rtpi-orchestrator/data/certs"
        "/opt/rtpi-orchestrator/data/portainer"
        "/var/log/rtpi-healer"
        "/data/rtpi-healer"
        "/data/backups"
        "/data/configs"
    )
    
    echo "Creating base system directories..."
    for dir in "${base_dirs[@]}"; do
        mkdir -p "$dir"
        chown -R 1000:1000 "$dir"
        chmod -R 755 "$dir"
        echo "✓ Created: $dir"
    done
}

# Initialize Empire C2 setup - Host-level configuration only (Empire runs natively)
init_empire() {
    echo "Initializing Empire C2 host-level configuration..."
    
    # Empire is installed natively via fresh-rtpi-pen.sh
    # This function only ensures native Empire can access any needed directories
    
    local empire_native_dir="/opt/Empire"
    if [ -d "$empire_native_dir" ]; then
        echo "✓ Native Empire installation found at $empire_native_dir"
        
        # Ensure proper permissions for native Empire
        chown -R root:root "$empire_native_dir"
        chmod -R 755 "$empire_native_dir"
        
        # Make ps-empire executable
        if [ -f "$empire_native_dir/ps-empire" ]; then
            chmod +x "$empire_native_dir/ps-empire"
            echo "✓ Native Empire permissions configured"
        fi
    else
        echo "ℹ️  Native Empire not found - will be installed by fresh-rtpi-pen.sh"
    fi
    
    echo "✓ Empire host-level initialization completed"
}

# Initialize orchestrator setup
init_orchestrator() {
    echo "Initializing RTPI Orchestrator..."
    
    local data_dir="/opt/rtpi-orchestrator/data"
    mkdir -p "$data_dir/certs" "$data_dir/portainer"
    
    # Create Portainer admin password hash if needed
    if [ ! -f "$data_dir/portainer_password" ]; then
        echo '$2a$10$N8XymdoNDQjHlraNJWM6JOhT8vjjyZO6zGQGFCEzLCYIyIkGxP6oa' > "$data_dir/portainer_password"
        echo "✓ Created Portainer admin password"
    fi
    
    chown -R 1000:1000 "$data_dir"
    chmod -R 755 "$data_dir"
    echo "✓ Orchestrator initialization completed"
}

# Validate SysReptor configuration
validate_sysreptor_config() {
    echo "Validating SysReptor configuration..."
    
    local config_file="/home/cmndcntrl/rtpi-pen/configs/rtpi-sysreptor/app.env"
    
    if [ ! -f "$config_file" ]; then
        echo "❌ SysReptor config file not found: $config_file"
        return 1
    fi
    
    # Check required variables
    local required_vars=(
        "SECRET_KEY"
        "POSTGRES_HOST"
        "POSTGRES_NAME"
        "POSTGRES_USER"
        "POSTGRES_PASSWORD"
        "REDIS_HOST"
        "REDIS_PASSWORD"
    )
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$config_file"; then
            echo "❌ Missing required variable: $var"
            return 1
        fi
    done
    
    echo "✓ SysReptor configuration validated"
}

# Create health check scripts
create_health_checks() {
    echo "Creating health check scripts..."
    
    local health_dir="/opt/rtpi-healer/health"
    mkdir -p "$health_dir"
    
    # Database health check
    cat > "$health_dir/check_database.sh" << 'EOF'
#!/bin/bash
# Database Health Check

check_kasm_db() {
    echo "Checking Kasm database..."
    if docker exec kasm_db pg_isready -U kasmapp -d kasm -h localhost; then
        echo "✓ Kasm database is healthy"
        return 0
    else
        echo "❌ Kasm database is not responding"
        return 1
    fi
}

check_sysreptor_db() {
    echo "Checking SysReptor database..."
    if docker exec sysreptor-db pg_isready -U sysreptor -d sysreptor -h localhost; then
        echo "✓ SysReptor database is healthy"
        return 0
    else
        echo "❌ SysReptor database is not responding"
        return 1
    fi
}

check_rtpi_db() {
    echo "Checking RTPI database..."
    if docker exec rtpi-database pg_isready -U rtpi -d rtpi_main -h localhost; then
        echo "✓ RTPI database is healthy"
        return 0
    else
        echo "❌ RTPI database is not responding"
        return 1
    fi
}

# Run all checks
check_kasm_db
check_sysreptor_db
check_rtpi_db
EOF
    
    # Redis health check
    cat > "$health_dir/check_redis.sh" << 'EOF'
#!/bin/bash
# Redis Health Check

check_kasm_redis() {
    echo "Checking Kasm Redis..."
    if docker exec kasm_redis redis-cli -a "CwoZWGpBk5PZ3zD79fIK" ping; then
        echo "✓ Kasm Redis is healthy"
        return 0
    else
        echo "❌ Kasm Redis is not responding"
        return 1
    fi
}

check_sysreptor_redis() {
    echo "Checking SysReptor Redis..."
    if docker exec sysreptor-redis redis-cli -a "sysreptorredispassword" ping; then
        echo "✓ SysReptor Redis is healthy"
        return 0
    else
        echo "❌ SysReptor Redis is not responding"
        return 1
    fi
}

check_rtpi_cache() {
    echo "Checking RTPI Cache..."
    if docker exec rtpi-cache redis-cli -p 6379 ping; then
        echo "✓ RTPI Cache is healthy"
        return 0
    else
        echo "❌ RTPI Cache is not responding"
        return 1
    fi
}

# Run all checks
check_kasm_redis
check_sysreptor_redis
check_rtpi_cache
EOF
    
    chmod +x "$health_dir"/*.sh
    chown -R 1000:1000 "$health_dir"
    echo "✓ Health check scripts created"
}

# Create monitoring dashboard
create_monitoring_dashboard() {
    echo "Creating monitoring dashboard..."
    
    local dashboard_dir="/opt/rtpi-healer/dashboard"
    mkdir -p "$dashboard_dir"
    
    cat > "$dashboard_dir/status.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>RTPI-PEN System Status</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: #2c3e50;
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 2.5em;
            font-weight: 300;
        }
        .subtitle {
            margin-top: 10px;
            opacity: 0.8;
            font-size: 1.1em;
        }
        .content {
            padding: 30px;
        }
        .service-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .service-card {
            border: 1px solid #ddd;
            border-radius: 8px;
            padding: 20px;
            transition: transform 0.3s ease;
        }
        .service-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .service-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }
        .service-name {
            font-size: 1.3em;
            font-weight: 600;
            color: #2c3e50;
        }
        .status-indicator {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            display: inline-block;
        }
        .status-running { background-color: #27ae60; }
        .status-restarting { background-color: #f39c12; }
        .status-stopped { background-color: #e74c3c; }
        .status-unknown { background-color: #95a5a6; }
        .service-info {
            color: #7f8c8d;
            font-size: 0.9em;
        }
        .refresh-btn {
            background: #3498db;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 1em;
            margin-top: 20px;
        }
        .refresh-btn:hover {
            background: #2980b9;
        }
        .timestamp {
            text-align: center;
            color: #7f8c8d;
            margin-top: 20px;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏥 RTPI-PEN System Status</h1>
            <div class="subtitle">Self-Healing Infrastructure Dashboard</div>
        </div>
        <div class="content">
            <div class="service-grid" id="serviceGrid">
                <!-- Services will be populated by JavaScript -->
            </div>
            <div style="text-align: center;">
                <button class="refresh-btn" onclick="refreshStatus()">🔄 Refresh Status</button>
            </div>
            <div class="timestamp" id="timestamp"></div>
        </div>
    </div>

    <script>
        function updateTimestamp() {
            document.getElementById('timestamp').textContent = 
                'Last updated: ' + new Date().toLocaleString();
        }

        function getStatusClass(status) {
            switch(status.toLowerCase()) {
                case 'running': return 'status-running';
                case 'restarting': return 'status-restarting';
                case 'stopped': case 'exited': return 'status-stopped';
                default: return 'status-unknown';
            }
        }

        function refreshStatus() {
            // This would normally fetch from the healer API
            // For now, we'll show a placeholder
            const services = [
                { name: 'RTPI Healer', status: 'running', info: 'Self-healing service active' },
                { name: 'Kasm Workspaces', status: 'running', info: 'Virtual desktop platform' },
                { name: 'SysReptor', status: 'running', info: 'Report generation system' },
                { name: 'PS Empire', status: 'running', info: 'C2 framework' },
                { name: 'RTPI Orchestrator', status: 'running', info: 'Container management' },
                { name: 'Database Services', status: 'running', info: 'PostgreSQL clusters' },
                { name: 'Cache Services', status: 'running', info: 'Redis instances' },
                { name: 'Proxy Services', status: 'running', info: 'Load balancing' }
            ];

            const grid = document.getElementById('serviceGrid');
            grid.innerHTML = '';

            services.forEach(service => {
                const card = document.createElement('div');
                card.className = 'service-card';
                card.innerHTML = `
                    <div class="service-header">
                        <div class="service-name">${service.name}</div>
                        <span class="status-indicator ${getStatusClass(service.status)}"></span>
                    </div>
                    <div class="service-info">${service.info}</div>
                `;
                grid.appendChild(card);
            });

            updateTimestamp();
        }

        // Initialize
        refreshStatus();
        setInterval(refreshStatus, 30000); // Refresh every 30 seconds
    </script>
</body>
</html>
EOF
    
    chown -R 1000:1000 "$dashboard_dir"
    chmod 644 "$dashboard_dir/status.html"
    echo "✓ Monitoring dashboard created"
}

# Create system recovery scripts
create_recovery_scripts() {
    echo "Creating system recovery scripts..."
    
    local recovery_dir="/opt/rtpi-healer/recovery"
    mkdir -p "$recovery_dir"
    
    # Emergency recovery script
    cat > "$recovery_dir/emergency_recovery.sh" << 'EOF'
#!/bin/bash
# Emergency Recovery Script
# Performs system-wide recovery actions

echo "🚨 Starting Emergency Recovery..."

# Stop all containers
echo "Stopping all containers..."
docker stop $(docker ps -q) 2>/dev/null || true

# Clean up resources
echo "Cleaning up resources..."
docker system prune -f
docker volume prune -f

# Restart critical services first
echo "Restarting critical services..."
docker-compose up -d rtpi-database rtpi-cache rtpi-healer

# Wait for database to be ready
echo "Waiting for database..."
sleep 30

# Restart application services
echo "Restarting application services..."
docker-compose up -d

echo "✅ Emergency recovery completed"
EOF
    
    # Configuration restore script
    cat > "$recovery_dir/restore_config.sh" << 'EOF'
#!/bin/bash
# Configuration Restore Script
# Restores configurations from backup

if [ $# -ne 1 ]; then
    echo "Usage: $0 <backup_directory>"
    exit 1
fi

BACKUP_DIR="$1"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Backup directory does not exist: $BACKUP_DIR"
    exit 1
fi

echo "🔄 Restoring configuration from: $BACKUP_DIR"

# Restore Kasm configs
if [ -d "$BACKUP_DIR/conf" ]; then
    cp -r "$BACKUP_DIR/conf" /opt/kasm/1.15.0/
    chown -R 1000:1000 /opt/kasm/1.15.0/conf
    echo "✓ Kasm configuration restored"
fi

# Restore project configs
if [ -d "$BACKUP_DIR/configs" ]; then
    cp -r "$BACKUP_DIR/configs" /home/cmndcntrl/rtpi-pen/
    echo "✓ Project configuration restored"
fi

# Restore docker-compose.yml
if [ -f "$BACKUP_DIR/docker-compose.yml" ]; then
    cp "$BACKUP_DIR/docker-compose.yml" /home/cmndcntrl/rtpi-pen/
    echo "✓ Docker Compose configuration restored"
fi

echo "✅ Configuration restore completed"
EOF
    
    chmod +x "$recovery_dir"/*.sh
    chown -R 1000:1000 "$recovery_dir"
    echo "✓ Recovery scripts created"
}

# Main initialization function
main() {
    echo "Starting comprehensive system initialization..."
    
    # Check if we're running as root
    if [ "$EUID" -ne 0 ]; then
        echo "❌ This script must be run as root"
        exit 1
    fi
    
    # Create base directories
    create_base_directories
    
    # Kasm is initialized natively via fresh-rtpi-pen.sh
    echo "ℹ️  Kasm Workspaces installed natively via fresh-rtpi-pen.sh"
    echo "ℹ️  Kasm available at: https://localhost:8443"
    
    # Initialize other services
    init_empire
    init_orchestrator
    
    # Validate configurations
    validate_sysreptor_config
    
    # Create monitoring and recovery infrastructure
    create_health_checks
    create_monitoring_dashboard
    create_recovery_scripts
    
    echo "✅ System initialization completed successfully!"
    echo "🏥 Self-healing infrastructure is ready"
    echo "📊 Dashboard available at: /opt/rtpi-healer/dashboard/status.html"
    echo "🔧 Recovery scripts available at: /opt/rtpi-healer/recovery/"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
