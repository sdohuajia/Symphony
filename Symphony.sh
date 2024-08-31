#!/bin/bash

# 脚本保存路径
SCRIPT_PATH="$HOME/Symphony.sh"

# 确保脚本以 root 权限运行
if [ "$(id -u)" -ne "0" ]; then
  echo "请以 root 用户或使用 sudo 运行此脚本"
  exit 1
fi

# 主菜单函数
function main_menu() {
    while true; do
        clear
        echo "脚本由大赌社区哈哈哈哈编写，推特 @ferdie_jhovie，免费开源，请勿相信收费"
        echo "================================================================"
        echo "节点社区 Telegram 群组: https://t.me/niuwuriji"
        echo "节点社区 Telegram 频道: https://t.me/niuwuriji"
        echo "节点社区 Discord 社群: https://discord.gg/GbMV5EcNWF"
        echo "退出脚本，请按键盘 ctrl + C 退出即可"
        echo "请选择要执行的操作:"
        echo "1) 安装并启动 Symphony 节点"
        echo "2) 创建验证者"  # 创建验证者选项
        echo "3) 委托"  # 委托选项
        echo "4) 删除节点"  # 删除节点选项
        echo "5) 查看日志"  # 查看日志选项
        echo "6) 下载快照"  # 下载快照选项
        echo "7) 查看同步状态"  # 查看同步状态选项
        echo "8) 退出"  # 退出选项
        read -p "请输入选项 [1-8]: " choice
        
        case $choice in
            1)
                install_and_start
                ;;
            2)
                create_validator  # 调用创建验证者函数
                ;;
            3)
                delegate
                ;;
            4)
                remove_node
                ;;
            5)
                view_logs
                ;;
            6)
                download_snapshot
                ;;
            7)
                check_sync_status
                ;;
            8)
                echo "退出脚本..."
                exit 0
                ;;
            *)
                echo "无效的选项，请重新选择。"
                sleep 2
                ;;
        esac
    done
}

# 安装并启动 Symphony 节点的函数
function install_and_start() {
    echo "开始安装并启动 Symphony 节点..."

    # 更新包列表
    echo "更新包列表..."
    apt-get update -q

    # 安装常用工具
    echo "安装 curl, git, jq, lz4 和 build-essential..."
    apt-get install -qy curl git jq lz4 build-essential

    # 升级现有包
    echo "升级现有包..."
    apt-get upgrade -qy

    # 安装 libssl-dev
    echo "安装 libssl-dev..."
    apt-get install -y libssl-dev

    # 检查是否已安装 Go
if ! command -v go &> /dev/null
then
    echo "Go 未安装，正在安装 Go..."

    # 安装 Go
    cd $HOME
    VER="1.22.3"
    wget "https://golang.org/dl/go$VER.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "go$VER.linux-amd64.tar.gz"
    rm "go$VER.linux-amd64.tar.gz"

    # 更新环境变量
    [ ! -f ~/.bash_profile ] && touch ~/.bash_profile
    echo "export PATH=$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile
    source ~/.bash_profile

    # 创建目录
    [ ! -d ~/go/bin ] && mkdir -p ~/go/bin

    # 验证 Go 安装
    go version
else
    echo "Go 已安装"
fi

    # 设置 Symphony 环境变量
    echo "设置 Symphony 环境变量..."
    echo "export SYMPHONY_PORT=35" >> $HOME/.bash_profile
    source $HOME/.bash_profile

    # 安装 Symphony
    echo "安装 Symphony..."
    cd $HOME
    rm -rf symphony
    git clone https://github.com/Orchestra-Labs/symphony
    cd symphony
    git checkout v0.3.0
    
    # 确保构建目录存在
    mkdir -p build

    # 构建项目
    make build
    if [ ! -f $HOME/symphony/build/symphonyd ]; then
        echo "构建失败，找不到 symphonyd 文件。"
        exit 1
    fi

    # 创建目录并移动文件
    echo "创建目录并移动文件..."
    mkdir -p ~/.symphonyd/cosmovisor/upgrades/0.3.0/bin
    mv $HOME/symphony/build/symphonyd ~/.symphonyd/cosmovisor/upgrades/0.3.0/bin/

    # 创建符号链接
    echo "创建符号链接..."
    sudo ln -s ~/.symphonyd/cosmovisor/upgrades/0.3.0 ~/.symphonyd/cosmovisor/current -f
    sudo ln -s ~/.symphonyd/cosmovisor/current/bin/symphonyd /usr/local/bin/symphonyd -f

    # 安装 cosmovisor
    echo "安装 cosmovisor..."
    go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.6.0

    # 切换回用户主目录
    cd $HOME

    # 配置服务但不启动
    echo "配置 symphonyd 服务..."
    sudo tee /etc/systemd/system/symphonyd.service > /dev/null << EOF
[Unit]
Description=symphony node service
After=network-online.target

[Service]
User=$USER
ExecStart=$(which cosmovisor) run start --home $HOME/.symphonyd
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
Environment="DAEMON_HOME=${HOME}/.symphonyd"
Environment="DAEMON_NAME=symphonyd"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:~/.symphonyd/cosmovisor/current/bin"

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd 配置并启用服务
    echo "重新加载 systemd 配置并启用服务..."
    sudo systemctl daemon-reload
    sudo systemctl enable symphonyd

    # 初始化 symphonyd
    echo "初始化 symphonyd..."
    symphonyd config chain-id symphony-testnet-3
    symphonyd config keyring-backend test
    symphonyd config node tcp://localhost:${SYMPHONY_PORT}657
    symphonyd init "RPCdot" --chain-id symphony-testnet-3

    # 下载配置文件
    echo "下载配置文件..."
    curl https://raw.githubusercontent.com/Orchestra-Labs/symphony/7acce0a194fd93fbaa8a0e1b49a15ce6251fa4dd/networks/symphony-testnet-3/genesis.json -o ~/.symphonyd/config/genesis.json
    curl https://raw.githubusercontent.com/MictoNode/symphony-cosmos/main/addrbook.json -o ~/.symphonyd/config/addrbook.json

    # 修改配置文件
    echo "修改配置文件..."
    sed -i.bak -e "s%:1317%:${SYMPHONY_PORT}317%g;
    s%:8080%:${SYMPHONY_PORT}080%g;
    s%:9090%:${SYMPHONY_PORT}090%g;
    s%:9091%:${SYMPHONY_PORT}091%g;
    s%:8545%:${SYMPHONY_PORT}545%g;
    s%:8546%:${SYMPHONY_PORT}546%g;
    s%:6065%:${SYMPHONY_PORT}065%g" $HOME/.symphonyd/config/app.toml

    sed -i.bak -e "s%:26658%:${SYMPHONY_PORT}658%g;
    s%:26657%:${SYMPHONY_PORT}657%g;
    s%:6060%:${SYMPHONY_PORT}060%g;
    s%:26656%:${SYMPHONY_PORT}656%g;
    s%^external_address = \"\"%external_address = \"$(wget -qO- eth0.me):${SYMPHONY_PORT}656\"%;
    s%:26660%:${SYMPHONY_PORT}660%g" $HOME/.symphonyd/config/config.toml

    # 配置 peers 和 seeds
    echo "配置 peers 和 seeds..."
    SEEDS="10838131d11f546751178df1e1045597aad6366d@34.41.169.77:26656"
    PEERS="eea2dc7e9abfd18787d4cc2c728689ad658cd3a2@34.66.161.223:26656"
    sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.symphonyd/config/config.toml

    # 配置 pruning 设置
    echo "配置 pruning 设置..."
    sed -i -e "s/^pruning *=.*/pruning = \"custom\"/" $HOME/.symphonyd/config/app.toml
    sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"100\"/" $HOME/.symphonyd/config/app.toml
    sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"10\"/" $HOME/.symphonyd/config/app.toml

    # 配置 gas 价格和 Prometheus
    echo "配置 gas 价格和 Prometheus..."
    sed -i 's|minimum-gas-prices =.*|minimum-gas-prices = "0note"|g' $HOME/.symphonyd/config/app.toml
    sed -i 's|^prometheus *=.*|prometheus = true|' $HOME/.symphonyd/config/config.toml
    sed -i -e 's|^indexer *=.*|indexer = "null"|' $HOME/.symphonyd/config/config.toml

    # 下载快照
    echo "下载快照..."
    echo "export SYMPHONY_SS_URL=paste-ss-url" >> $HOME/.bash_profile
    source $HOME/.bash_profile
    symphonyd tendermint unsafe-reset-all --home $HOME/.symphonyd
    if curl -s --head ${SYMPHONY_SS_URL} | head -n 1 | grep "200" > /dev/null; then
      curl ${SYMPHONY_SS_URL} | lz4 -dc - | tar -xf - -C $HOME/.symphonyd
    else
      echo "快照 URL 无效"
    fi

    # 用户选择创建钱包或导入钱包
    echo "请选择钱包操作: 创建新钱包 (输入 1) 或导入钱包 (输入 2)"
    read -p "您的选择: " choice
    if [ "$choice" -eq 1 ]; then
      symphonyd keys add wallet-name
    elif [ "$choice" -eq 2 ]; then
      symphonyd keys add wallet-name --recover
    else
      echo "无效的选择"
      exit 1
    fi

    # 启动服务
    echo "启动服务..."
    sudo systemctl start symphonyd

    echo "所有操作已完成。"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 委托功能函数
function delegate() {
    echo "开始委托..."
    read -p "请输入委托金额 (例如: 100000note): " amount
    symphonyd tx staking delegate $(symphonyd keys show wallet-name --bech val -a) $amount \
    --chain-id symphony-testnet-3 \
    --from "wallet-name" \
    --fees "800note" \
    --node=http://localhost:${SYMPHONY_PORT}657 \
    -y

    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 创建验证者功能函数
function create_validator() {
    echo "开始创建验证者..."
    read -p "请输入委托金额 (例如: 90000note): " amount
    symphonyd tx staking create-validator \
      --amount "$amount" \
      --pubkey $(symphonyd tendermint show-validator) \
      --moniker "myvalidator" \
      --identity "optional identity signature (ex. UPort or Keybase)" \
      --details "RPCdot.com 🐦" \
      --website "validator's (optional) website" \
      --chain-id symphony-testnet-3 \
      --commission-rate "0.05" \
      --commission-max-rate "0.2" \
      --commission-max-change-rate "0.01" \
      --min-self-delegation "1" \
      --fees "800note" \
      --from wallet-name \
      --node=http://localhost:${SYMPHONY_PORT}657 \
      -y

    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 删除节点功能函数
function remove_node() {
    echo "删除节点..."
    cd $HOME
    sudo systemctl stop symphonyd
    sudo systemctl disable symphonyd
    sudo rm -rf /etc/systemd/system/symphonyd.service
    sudo systemctl daemon-reload
    sudo rm -f /usr/local/bin/symphonyd
    sudo rm -f $(which symphonyd)
    sudo rm -rf $HOME/.symphonyd $HOME/symphony
    sed -i "/SYMPHONY_/d" $HOME/.bash_profile

    echo "节点已删除。"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 查看日志功能函数
function view_logs() {
    echo "查看日志..."
    journalctl -u symphonyd -f -o cat

    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 下载并恢复快照功能函数
function download_snapshot() {
    echo "安装 lz4..."
    sudo apt update && sudo apt install -y lz4

    echo "停止节点..."
    sudo systemctl stop symphonyd

    echo "备份数据..."
    sudo cp /root/.symphonyd/data/priv_validator_state.json /root/.symphonyd/priv_validator_state.json.backup

    echo "重置节点状态..."
    symphonyd tendermint unsafe-reset-all --home /root/.symphonyd --keep-addr-book

    echo "下载并恢复快照..."
    curl -# https://files.nodeshub.online/testnet/symphony/snapshot/symphony_snap.tar.lz4 | lz4 -dc - | tar -xf - -C /root/.symphonyd

    echo "下载并更新 addrbook.json..."
    wget --no-cache -O /root/.symphonyd/config/addrbook.json https://files.nodeshub.online/testnet/symphony/addrbook.json

    echo "恢复验证器状态文件..."
    sudo cp /root/.symphonyd/priv_validator_state.json.backup /root/.symphonyd/data/priv_validator_state.json

    echo "启动节点..."
    sudo systemctl start symphonyd

    echo "确保您的节点正在运行..."
    sudo systemctl status symphonyd
    sudo journalctl -u symphonyd -f
    
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 查看同步状态的函数
function check_sync_status() {
    local RPC_URL="http://localhost:26657"  # 本地 RPC 服务器的地址
    echo "查看同步状态..."

    # 获取状态信息
    local status
    status=$(curl -s "$RPC_URL/status")

    # 检查 curl 命令是否成功执行
    if [ $? -ne 0 ]; then
        echo "无法连接到本地 RPC 服务器。"
        return 1
    fi

    # 检查 JSON 数据是否有效
    if ! echo "$status" | jq . > /dev/null 2>&1; then
        echo "无法解析 JSON 数据。"
        return 1
    fi

    # 获取本地区块高度
    local local_block_height
    local_block_height=$(curl -s "$RPC_URL/status" | jq -r '.result.sync_info.latest_block_height')

    # 提取信息并格式化输出
    echo "=== 同步状态信息 ==="

    # 最新区块高度
    local latest_block_height
    latest_block_height=$(echo "$status" | jq -r '.result.sync_info.latest_block_height')
    echo "最新区块高度: $latest_block_height"

    # 最新区块时间
    local latest_block_time
    latest_block_time=$(echo "$status" | jq -r '.result.sync_info.latest_block_time')
    echo "最新区块时间: $latest_block_time"

    # 本地区块高度
    echo "本地区块高度: $local_block_height"

    # 是否在同步中
    local catching_up
    catching_up=$(echo "$status" | jq -r '.result.sync_info.catching_up')
    if [ "$catching_up" = "true" ]; then
        echo "节点正在同步中..."
    else
        echo "节点已完全同步。"
    fi

    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 运行主菜单
main_menu
