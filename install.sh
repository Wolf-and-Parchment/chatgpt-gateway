#!/bin/bash
if [ "$(id -u)" != "0" ]; then
   echo "该脚本必须以 root 权限运行" 1>&2
   exit 1
fi

# 向 /etc/sysctl.conf 添加禁用 IPv6 的设置
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf

# 应用系统配置更改
sysctl -p

echo "IPv6 已禁用，并已应用更改。"
CURRENT_DIR=$(
    cd "$(dirname "$0")"
    pwd
)

function log() {
    message="[Proxy Log]: $1 "
    echo -e "${message}" 2>&1 | tee -a ${CURRENT_DIR}/glider-install.log
}


log "======================= 开始安装 ======================="

function Check_Root() {
  if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 或 sudo 权限运行此脚本"
    exit 1
  fi
}


function Install_Docker(){
    if which docker >/dev/null 2>&1; then
        log "检测到 Docker 已安装，跳过安装步骤"
        log "启动 Docker "
        systemctl start docker 2>&1 | tee -a ${CURRENT_DIR}/install.log
    else
        log "... 在线安装 docker"

        if [[ $(curl -s ipinfo.io/country) == "CN" ]]; then
            sources=(
                "https://mirrors.aliyun.com/docker-ce"
                "https://mirrors.tencent.com/docker-ce"
                "https://mirrors.163.com/docker-ce"
                "https://mirrors.cernet.edu.cn/docker-ce"
            )

            get_average_delay() {
                local source=$1
                local total_delay=0
                local iterations=3

                for ((i = 0; i < iterations; i++)); do
                    delay=$(curl -o /dev/null -s -w "%{time_total}\n" "$source")
                    total_delay=$(awk "BEGIN {print $total_delay + $delay}")
                done

                average_delay=$(awk "BEGIN {print $total_delay / $iterations}")
                echo "$average_delay"
            }

            min_delay=${#sources[@]}
            selected_source=""

            for source in "${sources[@]}"; do
                average_delay=$(get_average_delay "$source")

                if (( $(awk 'BEGIN { print '"$average_delay"' < '"$min_delay"' }') )); then
                    min_delay=$average_delay
                    selected_source=$source
                fi
            done

            if [ -n "$selected_source" ]; then
                echo "选择延迟最低的源 $selected_source，延迟为 $min_delay 秒"
                export DOWNLOAD_URL="$selected_source"
                curl -fsSL "https://get.docker.com" -o get-docker.sh
                sh get-docker.sh 2>&1 | tee -a ${CURRENT_DIR}/install.log

                log "... 启动 docker"
                systemctl enable docker; systemctl daemon-reload; systemctl start docker 2>&1 | tee -a ${CURRENT_DIR}/install.log

                docker_config_folder="/etc/docker"
                if [[ ! -d "$docker_config_folder" ]];then
                    mkdir -p "$docker_config_folder"
                fi

                docker version >/dev/null 2>&1
                if [[ $? -ne 0 ]]; then
                    log "docker 安装失败"
                    exit 1
                else
                    log "docker 安装成功"
                fi
            else
                log "无法选择源进行安装"
                exit 1
            fi
        else
            log "非中国大陆地区，无需更改源"
            export DOWNLOAD_URL="https://download.docker.com"
            curl -fsSL "https://get.docker.com" -o get-docker.sh
            sh get-docker.sh 2>&1 | tee -a ${CURRENT_DIR}/install.log

            log "... 启动 docker"
            systemctl enable docker; systemctl daemon-reload; systemctl start docker 2>&1 | tee -a ${CURRENT_DIR}/install.log

            docker_config_folder="/etc/docker"
            if [[ ! -d "$docker_config_folder" ]];then
                mkdir -p "$docker_config_folder"
            fi

            docker version >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                log "docker 安装失败"
                exit 1
            else
                log "docker 安装成功"
            fi
        fi
    fi
}

function Install_Compose(){
    docker-compose version >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        log "... 在线安装 docker-compose"
        
        arch=$(uname -m)
		if [ "$arch" == 'armv7l' ]; then
			arch='armv7'
		fi
		curl -L https://resource.fit2cloud.com/docker/compose/releases/download/v2.22.0/docker-compose-$(uname -s | tr A-Z a-z)-$arch -o /usr/local/bin/docker-compose 2>&1 | tee -a ${CURRENT_DIR}/install.log
        if [[ ! -f /usr/local/bin/docker-compose ]];then
            log "docker-compose 下载失败，请稍候重试"
            exit 1
        fi
        chmod +x /usr/local/bin/docker-compose
        ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

        docker-compose version >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            log "docker-compose 安装失败"
            exit 1
        else
            log "docker-compose 安装成功"
        fi
    else
        compose_v=`docker-compose -v`
        if [[ $compose_v =~ 'docker-compose' ]];then
            read -p "检测到已安装 Docker Compose 版本较低（需大于等于 v2.0.0 版本），是否升级 [y/n] : " UPGRADE_DOCKER_COMPOSE
            if [[ "$UPGRADE_DOCKER_COMPOSE" == "Y" ]] || [[ "$UPGRADE_DOCKER_COMPOSE" == "y" ]]; then
                rm -rf /usr/local/bin/docker-compose /usr/bin/docker-compose
                Install_Compose
            else
                log "Docker Compose 版本为 $compose_v，可能会影响应用商店的正常使用"
            fi
        else
            log "检测到 Docker Compose 已安装，跳过安装步骤"
        fi
    fi
}
function Set_Port(){
    DEFAULT_PORT=`expr $RANDOM % 55535 + 10000`

    while true; do
        read -p "设置 glider 端口（默认为$DEFAULT_PORT）：" PANEL_PORT

        if [[ "$PANEL_PORT" == "" ]];then
            PANEL_PORT=$DEFAULT_PORT
        fi

        if ! [[ "$PANEL_PORT" =~ ^[1-9][0-9]{0,4}$ && "$PANEL_PORT" -le 65535 ]]; then
            echo "错误：输入的端口号必须在 1 到 65535 之间"
            continue
        fi

 	if command -v lsof >/dev/null 2>&1; then
	    if lsof -i:$PANEL_PORT >/dev/null 2>&1; then
 		echo "端口$PANEL_PORT被占用，请重新输入..."
   		continue
 	    fi
        elif command -v ss >/dev/null 2>&1; then
	    if ss -tlun | grep -q ":$PANEL_PORT " >/dev/null 2>&1; then
     		echo "端口$PANEL_PORT被占用，请重新输入..."
       		continue
     	    fi
	elif command -v netstat >/dev/null 2>&1; then
	    if netstat -tlun | grep -q ":$PANEL_PORT " >/dev/null 2>&1; then
	    	echo "端口$PANEL_PORT被占用，请重新输入..."
   		continue
	    fi
	fi

        log "您设置的端口为：$PANEL_PORT"
        break
    done
}

function Set_Username(){
    DEFAULT_USERNAME=`cat /dev/urandom | head -n 16 | md5sum | head -c 10`

    while true; do
        read -p "设置 glider 代理用户（默认为$DEFAULT_USERNAME）：" PANEL_USERNAME

        if [[ "$PANEL_USERNAME" == "" ]];then
            PANEL_USERNAME=$DEFAULT_USERNAME
        fi

        if [[ ! "$PANEL_USERNAME" =~ ^[a-zA-Z0-9_]{3,30}$ ]]; then
            echo "错误：用户仅支持字母、数字、下划线，长度 3-30 位"
            continue
        fi

        log "您设置的用户为：$PANEL_USERNAME"
        break
    done
}

function Set_Password(){
    DEFAULT_PASSWORD=`cat /dev/urandom | head -n 16 | md5sum | head -c 10`

    while true; do
        read -p "设置 glider 代理密码（默认为$DEFAULT_PASSWORD）：" PANEL_PASSWORD
	
        if [[ "$PANEL_PASSWORD" == "" ]];then
            PANEL_PASSWORD=$DEFAULT_PASSWORD
        fi

        if [[ ! "$PANEL_PASSWORD" =~ ^[a-zA-Z0-9_!@#$%*,.?]{3,30}$ ]]; then
            echo "错误：密码仅支持字母、数字、特殊字符（!@#$%*_,.?），长度 3-30 位"
            continue
        fi
        log "您设置的密码为：$PANEL_PASSWORD"
        break
    done
}



function InitNode() {
    log "配置 Proxy glider Service"
    git clone -b main  --depth=1 https://github.com/wm-chatgpt/chatgpt-proxy-node-deploy.git chatgpt-proxy-node
    cd chatgpt-proxy-node

    RUN_BASE_DIR=/opt/chatgpt-proxy-node
    mkdir -p $RUN_BASE_DIR
    rm -rf $RUN_BASE_DIR/*
    cp ./docker-compose.yml $RUN_BASE_DIR
    sed -i "s/8443:8443/$PANEL_PORT:8443/g" $RUN_BASE_DIR/docker-compose.yml
    echo listen=$PANEL_USERNAME:$PANEL_PASSWORD@:8443 > $RUN_BASE_DIR/glider.conf

    cd $RUN_BASE_DIR
    docker compose pull
    docker compose up -d --remove-orphans

## 提示信息
}


function Get_Ip(){
    active_interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}')
    if [[ -z $active_interface ]]; then
        LOCAL_IP="127.0.0.1"
    else
        LOCAL_IP=`ip -4 addr show dev "$active_interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}'`
    fi

    PUBLIC_IP=`curl -s https://api64.ipify.org`
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP="N/A"
    fi
    if echo "$PUBLIC_IP" | grep -q ":"; then
        PUBLIC_IP=[${PUBLIC_IP}]
        1pctl listen-ip ipv6
    fi
}

function Show_Result(){
    log ""
    log "=================感谢您的耐心等待，安装已经完成=================="
    log ""
    log "代理地址：socks5://$PANEL_USERNAME:$PANEL_PASSWORD@$PUBLIC_IP:$PANEL_PORT"
    log ""
    log "如果使用的是云服务器，请至安全组开放 $PANEL_PORT 端口"
    log ""
    log "================================================================"
}




function main(){
    Check_Root
    Install_Docker
    Install_Compose
    Set_Port
    Set_Username
    Set_Password
    InitNode
    Get_Ip
    Show_Result
}
main
