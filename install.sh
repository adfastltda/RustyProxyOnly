#!/bin/bash

# RustyProxy Installer - Versão Unificada

# Configurações globais
readonly SWAP_FILE="/swapfile"
readonly SWAP_SIZE="2G"
readonly LOG_FILE="/var/log/rustyproxy_install.log"
readonly STUNNEL_CONF="/etc/stunnel/stunnel.conf"
readonly CERT_DIR="/etc/stunnel"
readonly CERT_FILE="$CERT_DIR/cert.pem"
readonly KEY_FILE="$CERT_DIR/key.pem"
readonly SSH_CONFIG="/etc/ssh/sshd_config"
readonly MAX_STARTUPS="MaxStartups 5000:30:5000"
readonly TOOLS_DIR="/opt/tools"
readonly CHECKER_WEBSOCKET="$TOOLS_DIR/checker_websocket.py"
readonly CHECKER_STUNNEL="$TOOLS_DIR/checker_stunnel4.py"
readonly CRONTAB_FILE="/tmp/crontab.tmp"
readonly CRON_LINES=(
    "* * * * * python3 /opt/tools/checker_stunnel4.py >> /var/log/checker_stunnel4.log 2>&1"
    "* * * * * python3 /opt/tools/checker_websocket.py >> /var/log/checker_websocket.log 2>&1"
)
readonly RUSTYPROXY_DIR="/opt/rustyproxy"
readonly SINCRONIZAR_ORIGEM="/root/RustyProxyOnly/sincronizar.py"
readonly SINCRONIZAR_DESTINO="/root/sincronizar.py"

# Função para mostrar progresso
show_progress() {
    echo "Progresso: $1" | tee -a "$LOG_FILE"
}

# Função para tratamento de erros
error_exit() {
    echo -e "\nErro: $1" | tee -a "$LOG_FILE"
    exit 1
}

# Função para verificar comando
check_command() {
    command -v "$1" &>/dev/null || error_exit "Comando $1 não encontrado. Instale-o e tente novamente."
}

# Verifica se o script está sendo executado como root
if [ "$EUID" -ne 0 ]; then
    error_exit "Este script deve ser executado como root (use sudo)."
fi

# Configura log e ambiente
echo "Iniciando instalação do RustyProxy e configurações..." | tee "$LOG_FILE"
mkdir -p "$(dirname "$LOG_FILE")" || error_exit "Falha ao criar diretório de log"
export DEBIAN_FRONTEND=noninteractive

# Verificar sistema operacional
show_progress "Verificando sistema operacional..."
if ! command -v lsb_release &>/dev/null; then
    apt install -y lsb-release >> "$LOG_FILE" 2>&1 || error_exit "Falha ao instalar lsb-release"
fi
OS_NAME=$(lsb_release -is)
VERSION=$(lsb_release -rs)
case "$OS_NAME" in
    Ubuntu)
        case "$VERSION" in
            24.*|22.*|20.*|18.*)
                show_progress "Sistema Ubuntu $VERSION suportado, continuando..."
                ;;
            *)
                error_exit "Versão do Ubuntu não suportada. Use 18, 20, 22 ou 24."
                ;;
        esac
        ;;
    Debian)
        case "$VERSION" in
            12*|11*|10*|9*)
                show_progress "Sistema Debian $VERSION suportado, continuando..."
                ;;
            *)
                error_exit "Versão do Debian não suportada. Use 9, 10, 11 ou 12."
                ;;
        esac
        ;;
    *)
        error_exit "Sistema não suportado. Use Ubuntu ou Debian."
        ;;
esac

# Atualizar repositórios e instalar pacotes
show_progress "Atualizando repositórios e instalando pacotes..."
apt update -y >> "$LOG_FILE" 2>&1 || error_exit "Falha ao atualizar repositórios"
apt upgrade -y >> "$LOG_FILE" 2>&1 || error_exit "Falha ao atualizar sistema"
apt install -y htop curl build-essential git python3 python3-pip stunnel4 openssl lsb-release sed coreutils cron systemd openssh-server libc6-dev libssl-dev ca-certificates procps >> "$LOG_FILE" 2>&1 || error_exit "Falha ao instalar pacotes"

# Instalar Rust
show_progress "Instalando Rust..."
if ! command -v rustc &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >> "$LOG_FILE" 2>&1 || error_exit "Falha ao instalar Rust"
    source "$HOME/.cargo/env"
fi
check_command cargo

# Verificar comandos essenciais
show_progress "Verificando comandos essenciais..."
check_command apt
check_command systemctl
check_command openssl
check_command python3
check_command crontab
check_command git
check_command curl
check_command cargo || show_progress "Cargo não encontrado, será instalado com Rust..."

# Criar diretório RustyProxy
show_progress "Criando diretório $RUSTYPROXY_DIR..."
mkdir -p "$RUSTYPROXY_DIR" || error_exit "Falha ao criar $RUSTYPROXY_DIR"

# Instalar RustyProxy
show_progress "Compilando RustyProxy (pode levar algum tempo)..."
[ -d "/root/RustyProxyOnly" ] && rm -rf /root/RustyProxyOnly
git clone --branch main https://github.com/adfastltda/RustyProxyOnly.git /root/RustyProxyOnly >> "$LOG_FILE" 2>&1 || error_exit "Falha ao clonar RustyProxy"
mv /root/RustyProxyOnly/menu.sh "$RUSTYPROXY_DIR/menu" || error_exit "Falha ao mover menu"
cd /root/RustyProxyOnly/RustyProxy || error_exit "Diretório RustyProxy não encontrado"
cargo build --release --jobs "$(nproc)" >> "$LOG_FILE" 2>&1 || error_exit "Falha ao compilar RustyProxy"
mv ./target/release/RustyProxy "$RUSTYPROXY_DIR/proxy" || error_exit "Falha ao mover binário RustyProxy"

# Configurar sincronizar.py
show_progress "Configurando sincronizar.py..."
if [ -f "$SINCRONIZAR_ORIGEM" ]; then
    rm -f "$SINCRONIZAR_DESTINO" || show_progress "Aviso: Falha ao remover $SINCRONIZAR_DESTINO existente"
    mv "$SINCRONIZAR_ORIGEM" "$SINCRONIZAR_DESTINO" || error_exit "Falha ao mover sincronizar.py para $SINCRONIZAR_DESTINO"
    chmod 755 "$SINCRONIZAR_DESTINO" || error_exit "Falha ao definir permissões para $SINCRONIZAR_DESTINO"
else
    show_progress "Aviso: Arquivo $SINCRONIZAR_ORIGEM não encontrado, pulando configuração de sincronizar.py"
fi

# Configurar permissões do RustyProxy
show_progress "Configurando permissões do RustyProxy..."
chmod +x "$RUSTYPROXY_DIR/proxy" "$RUSTYPROXY_DIR/menu" || error_exit "Falha ao definir permissões"
ln -sf "$RUSTYPROXY_DIR/menu" /usr/local/bin/rustyproxy || error_exit "Falha ao criar link simbólico"

# Instalar e configurar STunnel
show_progress "Instalando STunnel..."
apt install -y stunnel4 openssl >> "$LOG_FILE" 2>&1 || error_exit "Falha ao instalar pacotes"
show_progress "Gerando certificados autoassinados..."
mkdir -p "$CERT_DIR" || error_exit "Falha ao criar $CERT_DIR"
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$KEY_FILE" -out "$CERT_FILE" \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=localhost" >> "$LOG_FILE" 2>&1 || error_exit "Falha ao gerar certificados"
    chmod 600 "$CERT_FILE" "$KEY_FILE" || error_exit "Falha ao configurar permissões dos certificados"
else
    show_progress "Certificados já existem, pulando geração..."
fi
show_progress "Criando configuração do STunnel..."
cat > "$STUNNEL_CONF" << 'EOF' || error_exit "Falha ao criar configuração do STunnel"
cert = /etc/stunnel/cert.pem
key = /etc/stunnel/key.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
sslVersion = all

[stunnel Port 443]
connect = 0.0.0.0:22
accept = 443
EOF
chmod 600 "$STUNNEL_CONF" || error_exit "Falha ao configurar permissões do STunnel"
if [ -f /etc/default/stunnel4 ]; then
    sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4 || error_exit "Falha ao habilitar STunnel"
else
    error_exit "Arquivo /etc/default/stunnel4 não encontrado."
fi
systemctl enable stunnel4 >> "$LOG_FILE" 2>&1 || error_exit "Falha ao habilitar serviço STunnel"
systemctl restart stunnel4 >> "$LOG_FILE" 2>&1 || error_exit "Falha ao reiniciar serviço STunnel"
if ! systemctl is-active --quiet stunnel4; then
    error_exit "O serviço STunnel não está ativo. Verifique os logs com 'journalctl -u stunnel4'."
fi

# Configurar MaxStartups
show_progress "Configurando MaxStartups em $SSH_CONFIG..."
if [ ! -f "$SSH_CONFIG" ]; then
    error_exit "Arquivo $SSH_CONFIG não encontrado."
fi
BACKUP_FILE="$SSH_CONFIG.bak.$(date +%F_%H-%M-%S)"
cp "$SSH_CONFIG" "$BACKUP_FILE" || error_exit "Falha ao criar backup do $SSH_CONFIG"
show_progress "Backup criado em $BACKUP_FILE"
sed -i '/^MaxStartups/d' "$SSH_CONFIG" || error_exit "Falha ao remover configuração existente de MaxStartups"
echo "$MAX_STARTUPS" >> "$SSH_CONFIG" || error_exit "Falha ao adicionar $MAX_STARTUPS ao $SSH_CONFIG"
if ! grep -q "^$MAX_STARTUPS" "$SSH_CONFIG"; then
    error_exit "Falha ao verificar a configuração $MAX_STARTUPS no $SSH_CONFIG"
fi
show_progress "Reiniciando serviço SSH..."
systemctl restart sshd >> "$LOG_FILE" 2>&1 || error_exit "Falha ao reiniciar serviço SSH"
if ! systemctl is-active --quiet sshd; then
    error_exit "O serviço SSH não está ativo. Verifique os logs com 'journalctl -u sshd'."
fi

# Configurar scripts checker
show_progress "Criando diretório $TOOLS_DIR..."
mkdir -p "$TOOLS_DIR" || error_exit "Falha ao criar $TOOLS_DIR"
show_progress "Configurando $CHECKER_WEBSOCKET..."
cat > "$CHECKER_WEBSOCKET" << 'EOF' || error_exit "Falha ao criar $CHECKER_WEBSOCKET"
#!/usr/bin/env python3
import socket
import os

def conectar_http(host, porta):
    sock = None  # Inicializa a variável sock

    try:
        # Estabelece a conexão TCP diretamente na porta 80
        sock = socket.create_connection((host, porta))
        print("Conectado a {} na porta {}".format(host, porta))

        # Envia uma solicitação HTTP GET simples
        requisicao = f"GET / HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n"
        sock.sendall(requisicao.encode('utf-8'))

        # Recebe a resposta
        resposta = sock.recv(4096).decode('utf-8')
        print("Resposta do servidor:")
        print(resposta)

    except Exception as e:
        erro = str(e)
        print("Erro ao conectar: {}".format(erro))

        # Reinicia o serviço websocket se o erro for "Connection refused"
        if "Connection refused" in erro:
            print("Reiniciando o serviço websocket...")
            os.system("/usr/sbin/service websocket restart")

    finally:
        if sock:
            sock.close()  # Fecha o socket principal se estiver aberto

if __name__ == "__main__":
    host = "premium.adfast.com.br"
    porta = 80
    conectar_http(host, porta)
EOF
chmod 755 "$CHECKER_WEBSOCKET" || error_exit "Falha ao definir permissões para $CHECKER_WEBSOCKET"

show_progress "Configurando $CHECKER_STUNNEL..."
cat > "$CHECKER_STUNNEL" << 'EOF' || error_exit "Falha ao criar $CHECKER_STUNNEL"
#!/usr/bin/env python3
import socket
import ssl
import os

def conectar_https(host, porta):
    contexto = ssl._create_unverified_context()
    sock = None  # Inicializa a variável sock

    try:
        # Estabelece a conexão TCP
        sock = socket.create_connection((host, porta))
        conexao_ssl = contexto.wrap_socket(sock, server_hostname=host)
        print("Conectado a {} na porta {}".format(host, porta))

        # Envia uma solicitação HTTP GET simples
        requisicao = f"GET / HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n"
        conexao_ssl.sendall(requisicao.encode('utf-8'))

        # Recebe a resposta
        resposta = conexao_ssl.recv(4096).decode('utf-8')
        print("Resposta do servidor:")
        print(resposta)

        conexao_ssl.close()  # Fecha a conexão SSL

    except Exception as e:
        erro = str(e)
        print("Erro ao conectar: {}".format(erro))

        # Reinicia o serviço stunnel4 se o erro for "Connection refused"
        if "Connection refused" in erro:
            print("Reiniciando o serviço stunnel4...")
            os.system("/usr/sbin/service stunnel4 restart")

    finally:
        if sock:
            sock.close()  # Fecha o socket principal se estiver aberto

if __name__ == "__main__":
    host = "premium.adfast.com.br"
    porta = 443
    conectar_https(host, porta)
EOF
chmod 755 "$CHECKER_STUNNEL" || error_exit "Falha ao definir permissões para $CHECKER_STUNNEL"
show_progress "Aviso: O script $CHECKER_WEBSOCKET depende de um serviço 'websocket'. Certifique-se de que ele está configurado."

# Configurar crontab
show_progress "Criando backup do crontab atual..."
CRONTAB_BACKUP="/tmp/crontab.bak.$(date +%F_%H-%M-%S)"
crontab -l > "$CRONTAB_BACKUP" 2>/dev/null || show_progress "Nenhum crontab existente, prosseguindo..."
show_progress "Backup do crontab salvo em $CRONTAB_BACKUP"
show_progress "Removendo entradas existentes do crontab..."
crontab -l 2>/dev/null | grep -v "checker_stunnel4.py" | grep -v "checker_websocket.py" > "$CRONTAB_FILE" || touch "$CRONTAB_FILE"
show_progress "Adicionando novas entradas ao crontab..."
for line in "${CRON_LINES[@]}"; do
    echo "$line" >> "$CRONTAB_FILE" || error_exit "Falha ao adicionar linha ao crontab"
done
crontab "$CRONTAB_FILE" || error_exit "Falha ao aplicar novo crontab"
rm -f "$CRONTAB_FILE" || show_progress "Aviso: Falha ao remover arquivo temporário $CRONTAB_FILE"
show_progress "Verificando crontab..."
if ! crontab -l | grep -q "checker_stunnel4.py" || ! crontab -l | grep -q "checker_websocket.py"; then
    error_exit "Falha ao verificar entradas no crontab"
fi

# Verificar se o swapfile já existe
show_progress "Verificando se o swapfile já existe..."
if [ -f "$SWAP_FILE" ]; then
    show_progress "Swapfile $SWAP_FILE já existe. Verificando se está ativo..."
    if swapon --show | grep -q "$SWAP_FILE"; then
        show_progress "Swapfile $SWAP_FILE já está ativo. Nenhuma ação necessária."
        exit 0
    else
        show_progress "Swapfile existe, mas não está ativo. Ativando..."
        swapon "$SWAP_FILE" >> "$LOG_FILE" 2>&1 || error_exit "Falha ao ativar swapfile existente"
        show_progress "Swapfile ativado com sucesso."
        exit 0
    fi
fi

# Verificar espaço em disco
show_progress "Verificando espaço em disco..."
AVAILABLE_SPACE=$(df -B1 / | tail -1 | awk '{print $4}')
MINIMUM_SPACE=$((2 * 1024 * 1024 * 1024))  # 2GB em bytes
if [ "$AVAILABLE_SPACE" -lt "$MINIMUM_SPACE" ]; then
    error_exit "Espaço insuficiente em disco. Necessário 2GB, disponível: $((AVAILABLE_SPACE / 1024 / 1024))MB"
fi

# Criar swapfile
show_progress "Criando swapfile de $SWAP_SIZE..."
fallocate -l "$SWAP_SIZE" "$SWAP_FILE" >> "$LOG_FILE" 2>&1 || error_exit "Falha ao criar swapfile"
chmod 600 "$SWAP_FILE" >> "$LOG_FILE" 2>&1 || error_exit "Falha ao definir permissões do swapfile"

# Configurar swapfile
show_progress "Configurando swapfile..."
mkswap "$SWAP_FILE" >> "$LOG_FILE" 2>&1 || error_exit "Falha ao configurar swapfile"
swapon "$SWAP_FILE" >> "$LOG_FILE" 2>&1 || error_exit "Falha ao ativar swapfile"

# Adicionar ao /etc/fstab
show_progress "Adicionando swapfile ao /etc/fstab..."
if ! grep -q "$SWAP_FILE" /etc/fstab; then
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab || error_exit "Falha ao adicionar swapfile ao /etc/fstab"
else
    show_progress "Swapfile já está configurado no /etc/fstab, pulando..."
fi

# Verificar se o swap está ativo
show_progress "Verificando status do swap..."
if swapon --show | grep -q "$SWAP_FILE"; then
    show_progress "Swap de 2GB ativado com sucesso."
else
    error_exit "Falha ao verificar swap ativo. Verifique com 'swapon --show'."
fi

# Exibir informações do swap
show_progress "Informações do swap:"
free -h | tee -a "$LOG_FILE"

#install speedtest
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
apt install speedtest

# Limpeza
show_progress "Limpando diretórios temporários..."
rm -rf /root/RustyProxyOnly || show_progress "Aviso: Falha ao remover diretório temporário /root/RustyProxyOnly"

# Finalização
echo "Instalação e configuração concluídas com sucesso." | tee -a "$LOG_FILE"
echo "Verifique os serviços com: systemctl status stunnel4 sshd" | tee -a "$LOG_FILE"
echo "Logs detalhados em: $LOG_FILE" | tee -a "$LOG_FILE"
echo "Logs dos checkers em: /var/log/checker_stunnel4.log e /var/log/checker_websocket.log" | tee -a "$LOG_FILE"
echo "Configuração do swap concluída com sucesso." | tee -a "$LOG_FILE"
echo "Logs detalhados em: $LOG_FILE" | tee -a "$LOG_FILE"
echo "Digite 'rustyproxy' para acessar o menu." | tee -a "$LOG_FILE"
echo -e "${VERDE}BadVPN instalado/atualizado e rodando via systemd!${RESET}" | tee -a "$LOG_FILE"
echo -e "${BRANCO}Use os seguintes comandos para gerenciar o BadVPN:${RESET}" | tee -a "$LOG_FILE"
echo -e "${VERMELHO} systemctl start badvpn${RESET} - ${BRANCO}Iniciar manualmente${RESET}" | tee -a "$LOG_FILE"
echo -e "${VERMELHO} systemctl stop badvpn${RESET} - ${BRANCO}Parar o serviço${RESET}" | tee -a "$LOG_FILE"
echo -e "${VERMELHO} systemctl restart badvpn${RESET} - ${BRANCO}Reiniciar o serviço${RESET}" | tee -a "$LOG_FILE"
echo -e "${VERMELHO} systemctl status badvpn${RESET} - ${BRANCO}Ver status e logs${RESET}" | tee -a "$LOG_FILE"
reboot
