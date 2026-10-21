#!/usr/bin/env bash
# ==========================================================
#  Install Nginx Proxy Manager (Docker) - otomatis
#  Cara pakai:
#    wget <URL_FILE>/install.sh
#    sudo bash install.sh
# ==========================================================

set -e

# --- Warna output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Harus dijalankan sebagai root ---
if [ "$(id -u)" -ne 0 ]; then
    error "Script ini harus dijalankan sebagai root. Gunakan: sudo bash install.sh"
    exit 1
fi

# --- User asli (kalau pakai sudo) ---
REAL_USER="${SUDO_USER:-root}"

# ----------------------------------------------------------
# 1. Cek port 80, 81, dan 443
# ----------------------------------------------------------
info "[1/6] Mengecek port 80, 81, dan 443..."
USED_PORTS=$(ss -tuln | grep -E ':(80|81|443)\s' || true)

if [ -n "$USED_PORTS" ]; then
    warn "Ada port yang sudah dipakai:"
    echo "$USED_PORTS"
    # Kalau yang memakai port adalah container NPM sendiri, lanjut saja
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^nginxproxymanager$'; then
        warn "Port dipakai oleh container nginxproxymanager yang sudah ada, lanjut..."
    else
        error "Matikan service yang memakai port tersebut dulu (mis. nginx/apache), lalu jalankan ulang script ini."
        exit 1
    fi
else
    info "Port 80, 81, 443 aman (belum dipakai)."
fi

# ----------------------------------------------------------
# 2. Update VPS
# ----------------------------------------------------------
info "[2/6] Update & upgrade VPS..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y && apt install build-essential curl -y

# ----------------------------------------------------------
# 3. Install Docker
# ----------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
    info "[3/6] Docker sudah terinstall, skip instalasi."
else
    info "[3/6] Menginstall Docker..."
    curl -sSL https://get.docker.com | sh
fi

systemctl enable --now docker

if [ "$REAL_USER" != "root" ]; then
    usermod -aG docker "$REAL_USER"
    info "User '$REAL_USER' ditambahkan ke grup docker (berlaku setelah logout/login ulang)."
fi

# ----------------------------------------------------------
# 4. Cek versi Docker
# ----------------------------------------------------------
info "[4/6] Versi Docker:"
docker --version

# ----------------------------------------------------------
# 5. Pull image Nginx Proxy Manager
# ----------------------------------------------------------
info "[5/6] Menarik image jc21/nginx-proxy-manager:latest..."
docker pull jc21/nginx-proxy-manager:latest

# ----------------------------------------------------------
# 6. Jalankan container
# ----------------------------------------------------------
info "[6/6] Menjalankan container Nginx Proxy Manager..."

# Data disimpan di home user yang menjalankan script
if [ "$REAL_USER" = "root" ]; then
    NPM_DIR="/root/npm"
else
    NPM_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)/npm"
fi

mkdir -p "$NPM_DIR/data" "$NPM_DIR/letsencrypt"

# Hapus container lama kalau ada (data tetap aman di volume)
if docker ps -a --format '{{.Names}}' | grep -q '^nginxproxymanager$'; then
    warn "Container lama ditemukan, dihapus dan dibuat ulang (data tetap aman)..."
    docker rm -f nginxproxymanager >/dev/null
fi

docker run -d \
  --name nginxproxymanager \
  -p 80:80 \
  -p 81:81 \
  -p 443:443 \
  -v "$NPM_DIR/data":/data \
  -v "$NPM_DIR/letsencrypt":/etc/letsencrypt \
  --restart unless-stopped \
  jc21/nginx-proxy-manager:latest

# ----------------------------------------------------------
# Selesai
# ----------------------------------------------------------
SERVER_IP=$(curl -s4 ifconfig.me || hostname -I | awk '{print $1}')

echo ""
info "Instalasi selesai!"
echo "----------------------------------------------"
echo " Buka di browser : http://${SERVER_IP}:81"
echo " Email default   : admin@example.com"
echo " Password default: changeme"
echo " (Wajib diganti saat login pertama)"
echo " Data tersimpan  : $NPM_DIR"
echo "----------------------------------------------"
echo "Cek status container: docker ps"
