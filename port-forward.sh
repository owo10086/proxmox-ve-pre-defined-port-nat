#!/bin/bash

# 提示用户输入参数
read -p "请输入网卡名称（如 eth0）: " device
read -p "请输入网络段（如 192.168.0.0/24）: " subnet
read -p "请输入起始端口（如 21000）: " startPort
read -p "请输入每个主机号的端口数量: " portPerHost
read -p "请输入本机 IP: " ip
read -p "是否启用测试模式？输入 yes 启用，其他则不启用: " test_mode

# 检测网络段是否 CIDR
if [[ $subnet != *"/"* ]]; then
    echo "网络段必须是 CIDR 格式！"
    exit 1
fi  

# 验证起始端口和每个主机号的端口数量大于等于0
if [[ $startPort -lt 0 || $portPerHost -lt 0 ]]; then
    echo "起始端口和每个主机号的端口数量必须大于等于0！"
    exit 1
fi

# 设置 NAT 转发规则
echo "CIDR 是 ${ip}。"
iptables -t nat -A POSTROUTING -s ${ip} -o ${device} -j MASQUERADE

# 去除 ip 的主机号和网段
ip=${ip%.*}

# portPerHost + 1
portPerHost=$((portPerHost + 1))

# 清除旧的iptables规则
iptables -t nat -F
iptables -t nat -X
iptables -t nat -Z
iptables -F
iptables -X
iptables -Z

# 设置默认策略
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 启用IP转发
echo 1 > /proc/sys/net/ipv4/ip_forward

# 计算每个主机号的端口范围
function calculatePortRanges() {
    hostNumber=$1

    startPortNumber=$((startPort + (hostNumber * portPerHost)))
    endPortNumber=$((startPortNumber + portPerHost - 1))

    echo "IP地址 ${ip}.${hostNumber} 对应的端口范围是 ${startPortNumber} 到 ${endPortNumber}。"
}

# 创建新的iptables规则
function createPortForwardingRule() {
    set -x

    hostNumber=$1

    startPortNumber=$((startPort + (hostNumber * portPerHost)))
    endPortNumber=$((startPortNumber + portPerHost - 1))

    echo "IP ${ip}.${hostNumber} 的 SSH 端口是 ${startPortNumber}。"
    iptables -t nat -A PREROUTING -i ${device} -p tcp --dport ${startPortNumber} -j DNAT --to ${ip}.${hostNumber}:22
    iptables -t nat -A PREROUTING -i ${device} -p udp --dport ${startPortNumber} -j DNAT --to ${ip}.${hostNumber}:22

    echo "IP ${ip}.${hostNumber} 的 RDP 端口是 $((startPortNumber + 1))。"
    iptables -t nat -A PREROUTING -i ${device} -p tcp --dport $((startPortNumber + 1)) -j DNAT --to ${ip}.${hostNumber}:3389
    iptables -t nat -A PREROUTING -i ${device} -p udp --dport $((startPortNumber + 1)) -j DNAT --to ${ip}.${hostNumber}:3389

    startPortNumber=$((startPortNumber + 2))
    echo "起始端口号是 ${startPortNumber}。"
    endPortNumber=$((endPortNumber))

    for ((portNumber = startPortNumber; portNumber <= endPortNumber; portNumber++)); do
        echo "IP ${ip}.${hostNumber} 的端口是 ${portNumber}。"
        iptables -t nat -A PREROUTING -i ${device} -p tcp --dport ${portNumber} -j DNAT --to ${ip}.${hostNumber}:${portNumber}
        iptables -t nat -A PREROUTING -i ${device} -p udp --dport ${portNumber} -j DNAT --to ${ip}.${hostNumber}:${portNumber}
    done
    
    set +x
}

# 循环遍历主机号
for hostNumber in $(seq 1 254); do
    if [ "$test_mode" == "yes" ]; then
        calculatePortRanges $hostNumber
    else
        createPortForwardingRule $hostNumber
    fi
done

# 保存iptables规则
iptables-save > /etc/iptables.rules
