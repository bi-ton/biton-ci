#!/bin/bash
set -eu

GlobalEnv=.env
BranchEnv=env/.env

function LoadEnv {
    if [ -f .env ]; then
        export $(echo $(cat $1 | sed 's/#.*//g'| xargs) | envsubst)
    fi
}

LoadEnv $GlobalEnv

Pwd=$PWD
Company=$(echo $COMPANY | awk '{print tolower($0)}')
Branches=$(echo -e $(ls -1 $BranchEnv* | cut -c $((${#BranchEnv}+1))- | sed "s/.//" | sed "s/^$/$PROD_BRANCH/" | sed "s/example//"))
Components=$(echo "$COMPONENTS" | tr , ' ')
DockerRegistry=$CI_HOST:$REGISTRY_PORT
WorkDir=$(dirname $Pwd)
SrcDir=$WorkDir/src

Red='\e[1;31m'
Green='\e[1;32m'
Yellow='\e[1;33m'
Blue='\e[1;34m'
Purple='\e[1;35m'
Cyan='\e[1;36m'
NC='\e[0m'

echo -e "${Cyan}"
echo "company    : $Company"
echo "host       : $CI_HOST"
echo "branches   : $Branches"
echo "components : $Components"
echo "registry   : $DockerRegistry"
echo "pwd        : $Pwd"
echo "work dir   : $WorkDir"
echo "src dir    : $SrcDir"
echo -e "${NC}"

export REGISTRY=$DockerRegistry

function ElapsedTime() {
    local timestamp=$1
    echo "$(date -d @$(($(date +%s)-$timestamp)) +"%M:%Ss")"
}

function Notify {
    msg=$1
    url="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    curl -s -o /dev/null -X POST $url -d chat_id=$BOT_CHAT_ID -d parse_mode="markdown" -d text="$msg" || true
}

function NotifyBuild {
    GitLastCommit
    local icon=$1
    local name=$2
    local time=''
    shift
    shift
    if (( "$#" )); then
        time=$1
    fi
    Notify "$icon \`$Component\` ___""$Branch""___ ***$name*** $time"$'\n'"$LastCommitInfo"
}

function NotifyDeploy {
    GitLastCommit
    local icon=$1
    local name=$2
    local time=''
    shift
    shift
    if (( "$#" )); then
        time=$1
    fi
    Notify "$icon \`$Component\` ___""$Branch""___ ***$name*** $time"
}

function NotifyBackup {
    GitLastCommit
    local icon=$1
    local name=$2
    local time=''
    shift
    shift
    if (( "$#" )); then
        time=$1
    fi
    Notify "$icon \`db\` ___""$Branch""___ ***$name*** $time"
}

function GenSshKey {
    cd $Pwd
    local key='github.key'
    ssh-keygen -q -t ed25519 -N '' -f $key
    cat "$key.pub" >> ~/.ssh/authorized_keys
    chmod og-wx ~/.ssh/authorized_keys
    echo -e "${Red}"
    cat "$key"
    echo -e "${NC}"
    rm "$key"*
    echo -e "set private key to secret ${Purple}SSH_KEY${NC} and ${Red}$CI_HOST${NC} to ${Purple}SSH_HOST${NC} in github repositories:"
    for component in $Components; do
        echo "https://github.com/$Company/$component/settings/secrets/actions"
    done
    key='n'
    until [ $key == 'y' ]; do
        read -n 1 -p "continue? y/n: " key && echo
    done
}

function CheckComponent {
    local name=$1
    local found=false
    for component in $Components; do
        if [ $component == "$name" ]; then
            found=true
            break
        fi
    done
    if [ "$found" = false ]; then
        echo -e "${Red}Error:${NC} component $name not found"
        exit 1
    fi
}

function CheckBranch {
    local name=$1
    local found=false
    for branch in $Branches; do
        if [ $branch == "$name" ]; then
            found=true
            break
        fi
    done
    if [ "$found" = false ]; then
        echo -e "${Red}Error:${NC} branch $name not found"
        exit 1
    fi
}

function GitLastCommit {
    LastCommitInfo=$(git log -1 --pretty='format:___%h___ ***%an***%n%s')
}

function Action {
    echo -e "${Purple}[!] $1${NC}"
}

function ActionFinish {
    Action "$1 completed successfully!"
}

function GitClone {
    Name=$1
    cd $WorkDir
    git clone https://github.com/msw-x/$Name
    cd $Name
}

function DockerBuildAndPush {
    Name=$1
    docker build -f docker/Dockerfile.$Name -t $DockerRegistry/$Name .
    docker push $DockerRegistry/$Name
}

function LoadBranchEnv {
    branch=$1
    file=$(echo -e ".$branch" | sed "s/.$PROD_BRANCH//")
    file=$BranchEnv$file
    LoadEnv $file
}

function InstallTools {
    Action 'install tools'
    apt update
    apt install -y postgresql-client
    apt install -y docker-compose python3-pip
    pip install paramiko
    sed -e "s/HOST/$DockerRegistry/g" docker/daemon.json > /etc/docker/daemon.json
    systemctl restart docker
    mkdir -p $WorkDir
}

function InstallDockerRegistry {
    Action 'install docker registry'
    GitClone 'docreg'
    export PORT=$REGISTRY_PORT
    docker-compose up -d
}

function BuildHardwareMonitor {
    Action 'build hardware monitor'
    name='hwmon'
    GitClone $name
    DockerBuildAndPush 'grafana'
    DockerBuildAndPush 'prometheus'
    cd ..
    rm -r $name
}

function InstallHardwareMonitor {
    Action 'install hardware monitor'
    cd $Pwd
    docker-compose -f docker/hwmon.yaml up -d
}

function BuildSws {
    Action 'build sws'
    name='sws'
    GitClone $name
    cp sws.conf.example sws.conf
    touch routes.lst
    docker build -t $DockerRegistry/$name . --network host
    docker push $DockerRegistry/$name
    cd ..
    rm -r $name
}

function CloneRepositories {
    Action 'clone repositories'
    for Branch in $Branches; do
        echo "branch: $Branch"
        mkdir -p $SrcDir/$Branch
        for component in $Components; do
            echo "component: $component"
            cd $SrcDir/$Branch
            git clone git@github.com:$Company/$component
            cd $component
            git checkout $Branch
        done
    done
}

function InstallToolsToHosts {
    Action 'copy ssh public keys and install tools to hosts'
    cd $Pwd
    for Branch in $Branches; do
        echo "branch: $Branch"
        LoadBranchEnv $Branch
        ./ssh/tools.sh $BT_HOST $UI_HOST
        host=$DB_HOST
        Component="biton-db"
        RemoteDockerCompose up -d
    done
}

function InstallApp {
    Action 'install app'
    cd $Pwd
    app='ci'
    dir='/usr/local/bin'
    cp $app $dir
    sed -i "s|INSTALL_DIR|$Pwd|" "$dir/$app"
}

function Init {
    GenSshKey
    InstallTools
    InstallDockerRegistry
    BuildHardwareMonitor
    InstallHardwareMonitor
    BuildSws
    CloneRepositories
    InstallToolsToHosts
    InstallApp
}

function Prune {
    docker system prune -f
    docker volume prune -f
}

function Remove {
    docker-compose -f docker/hwmon.yaml down -v
    cd ..
    rm -r src
    cd docreg
    docker-compose down -v
    cd ..
    rm -r docreg
    docker rmi -f $(docker images -aq)
    Prune
}

function SetHost {
    export SUFFIX=$suffix
    if [ $Component == "biton" ]; then
        host=$BT_HOST
    elif [ $Component == "biton-ui" ]; then
        host=$UI_HOST
    fi
}

function RemoteDockerCompose {
    cd $Pwd
    SetSuffix
    SetHost
    docker-compose -H "ssh://root@$host" -f "docker/$Component.yaml" $*
}

function SetSuffix {
    suffix=''
    if [ "$Branch" != "$PROD_BRANCH" ]; then
        suffix="-$Branch"
    fi
}

function RemoveDangling {
    docker rmi -f $(docker images --filter="dangling=true" -q) || true
}

function Build {
    local tm=$(date +%s)
    Action "build $Component $Branch"
    cd $Pwd
    cd "$SrcDir/$Branch/$Component"
    git pull
    NotifyBuild "⚒" "build"
    if [ $Component == "biton" ]; then
        cp biton.conf.example biton.conf
    fi
    docker build -t $DockerRegistry/$Component$suffix .
    docker push $DockerRegistry/$Component$suffix
    RemoveDangling
    NotifyBuild "✅" "builded" "$(ElapsedTime $tm)"
    ActionFinish 'build'
}

function Deploy {
    local tm=$(date +%s)
    Action "deploy $Component $Branch"
    cd $Pwd
    NotifyDeploy "🚀" "deploy"
    RemoteDockerCompose pull
    RemoteDockerCompose up -d
    docker -H "ssh://root@$host" system prune -f
    NotifyDeploy "✅" "deployed" "$(ElapsedTime $tm)"
    ActionFinish 'deploy'
}

function Update {
    Build $*
    Deploy $*
}

function UpdateBranch {
    branch=$1
    for component in $Components; do
        Run "update" $component $branch
    done
}

function UpdateAll {
    for branch in $Branches; do
        UpdateBranch $branch
    done
}

function Down {
    Action "down $Component $Branch"
    cd $Pwd
    RemoteDockerCompose down
    ActionFinish 'down'
}

function Restart {
    Action "restart $Component $Branch"
    cd $Pwd
    RemoteDockerCompose restart
    ActionFinish 'restart'
}

function CheckDisk {
    local dfi=$(df -h . | grep '/')
    local size=$(echo $dfi | awk '{print $2}')
    local used=$(echo $dfi | awk '{print $3}')
    local free=$(echo $dfi | awk '{print $4}')
    local use=$(echo $dfi | awk '{print $5}')
    local m="⚠️***Disk warning***"$'\n'"\`Used: $used $use\`"$'\n'"\`Free: $free\`"$'\n'"\`Size: $size\`"
    use=${use::-1}
    if (( $use > 80 )); then
        Notify "$m"
    fi
}

function Run {
    if (( "$#" )); then
        cmd=$1
        shift
        if [ $cmd == "init" ]; then
            Action 'init'
            Init
            ActionFinish 'init'
        elif [ $cmd == "prune" ]; then
            Action 'prune'
            Prune
            ActionFinish 'prune'
        elif [ $cmd == "remove" ]; then
            Action 'remove'
            Remove
            ActionFinish 'remove'
        elif [ $cmd == "update-all" ]; then
            if (( "$#" )); then
                Branch=$1
                shift
                UpdateBranch
            else
                UpdateAll
            fi
        else
            Component=$1
            shift
            if (( "$#" )); then
                Branch=$1
                shift
            else
                Branch=$PROD_BRANCH
            fi
            CheckComponent $Component
            CheckBranch $Branch
            LoadBranchEnv $Branch
            SetSuffix
            if [ $cmd == "build" ]; then
                Build
            elif [ $cmd == "deploy" ]; then
                Deploy $*
            elif [ $cmd == "update" ]; then
                Update $*
            elif [ $cmd == "down" ]; then
                Down
            elif [ $cmd == "restart" ]; then
                Restart
            fi
        fi
        CheckDisk
    else
        echo 'usage:'
        echo '  init                            - prepare all servers'
        echo '  prune                           - prune docker artifacts'
        echo '  remove                          - cancel init for it server'
        echo '  build      <component> [branch] - build component'
        echo '  deploy     <component> [branch] - deploy component to remove server'
        echo '  update     <component> [branch] - build and deploy component'
        echo '  down       <component> [branch] - down component on remote server'
        echo '  restart    <component> [branch] - restart component on remote server'
        echo '  update-all             [branch] - update all components'
    fi
}

Run $*
