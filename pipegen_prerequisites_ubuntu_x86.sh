#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo"
  exit 1
fi

# Setting up logging

LOG="/var/log/docker-nvidia-setup.log"

# Logging
exec > >(tee -a "$LOG") 2>&1

echo "==== Setup Started: $(date) ===="

trap "echo 'Interrupted by user'; exit 1" INT

export DEBIAN_FRONTEND=noninteractive

echo "==== PipeGen Pre-requisite setup===="
echo "Based on official documentation as of: 22 June 2026"
echo ""
echo "This script will install the following components:"
echo "  1. Docker"
echo "  2. NVIDIA Container Toolkit"
echo "  3. socat"
echo ""

# Confirmation (skip with -y/--yes, or when not running interactively)
ASSUME_YES=0
[[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]] && ASSUME_YES=1

if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
    read -r -p "Proceed with installation? [y/N]: " CONFIRM </dev/tty
    case "$CONFIRM" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Installation cancelled."; exit 0 ;;
    esac
fi
echo ""

# ---------------------------------------------------
# 0. OS Compatibility Check
# ---------------------------------------------------
if [ -f /etc/os-release ]; then
    . /etc/os-release
else
    echo "Cannot detect OS. /etc/os-release not found."
    exit 1
fi

if [[ "$ID" != "ubuntu" ]]; then
    echo "Unsupported OS: $ID"
    echo "This script only supports Ubuntu."
    exit 1
fi

VERSION_NUM=$(echo "$VERSION_ID" | cut -d. -f1)

if (( VERSION_NUM < 22 || VERSION_NUM > 26 )); then
    echo "Unsupported Ubuntu version: $VERSION_ID"
    echo "Supported versions: 22.04 to 26.04"
    exit 1
fi

echo "Detected OS: Ubuntu $VERSION_ID (Supported)"
echo ""

# ---------------------------------------------------
# 0.5 Pre-flight Checks
# ---------------------------------------------------
echo "Running pre-flight checks..."

MIN_FREE_GB=2            # hard minimum free space on / required (GB)
RECOMMENDED_FREE_GB=40     # recommended free space on / (GB)
APT_LOCK_TIMEOUT=300       # max seconds to wait for apt/dpkg locks

# --- Internet connectivity ---
echo "  -> Checking internet connectivity..."
if ! curl -fsS --retry 3 --retry-delay 3 --connect-timeout 10 \
          -o /dev/null "https://www.google.com/generate_204"; then
    echo "ERROR: No stable internet connection detected."
    echo "       A stable internet connection is required for this setup."
    exit 1
fi
echo "     Internet: OK"

# --- Free disk space on / ---
echo "  -> Checking available disk space..."
FREE_GB=$(df -P --block-size=G / | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
if (( FREE_GB < MIN_FREE_GB )); then
    echo "WARNING: At least ${MIN_FREE_GB} GB of free space is required for the"
    echo "         pre-requisites, but only ${FREE_GB} GB is available on '/'."
    if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
        read -r -p "Do you want to free up some space, or continue anyway? [continue/exit]: " DISK_ANS </dev/tty
        case "$DISK_ANS" in
            [cC]|[cC][oO][nN][tT][iI][nN][uU][eE]) echo "     Continuing with low disk space..." ;;
            *) echo "Please free up some space and run the script again."; exit 1 ;;
        esac
    else
        echo "     Continuing with low disk space (non-interactive)..."
    fi
elif (( FREE_GB < RECOMMENDED_FREE_GB )); then
    echo "     Disk: ${FREE_GB} GB free (OK, but ideally you should have ${RECOMMENDED_FREE_GB} GB)."
else
    echo "     Disk: ${FREE_GB} GB free (OK)"
fi

# --- apt / dpkg locks ---
echo "  -> Checking for apt/dpkg locks..."
LOCK_FILES=(
    /var/lib/dpkg/lock
    /var/lib/dpkg/lock-frontend
    /var/lib/apt/lists/lock
    /var/cache/apt/archives/lock
)
WAITED=0
while :; do
    LOCKED=""
    # Only the actual lock files are authoritative. We intentionally do NOT
    # match on process names (e.g. pgrep unattended-upgr): the long-lived
    # 'unattended-upgrade-shutdown' daemon runs from boot to shutdown waiting
    # for a signal, holds no lock, and would cause an endless false "busy".
    for lf in "${LOCK_FILES[@]}"; do
        if fuser "$lf" >/dev/null 2>&1; then
            LOCKED="$lf"
            break
        fi
    done
    [ -z "$LOCKED" ] && break

    if (( WAITED >= APT_LOCK_TIMEOUT )); then
        echo "ERROR: apt/dpkg is locked by $LOCKED after ${APT_LOCK_TIMEOUT}s."
        echo "       Another package operation is in progress. Try again later."
        exit 1
    fi
    echo "     apt/dpkg busy ($LOCKED). Waiting... (${WAITED}/${APT_LOCK_TIMEOUT}s)"
    sleep 5
    WAITED=$((WAITED + 5))
done
echo "     apt/dpkg: free"

echo "Pre-flight checks passed."
echo ""

# ---------------------------------------------------
# 1. Check & Install Docker
# ---------------------------------------------------
if command -v docker >/dev/null 2>&1; then
    echo " Docker already installed. Skipping..."
else
    echo "[1/5] Installing Docker..."

    apt-get update
    apt-get install -y ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      -o /etc/apt/keyrings/docker.asc

    chmod a+r /etc/apt/keyrings/docker.asc

    tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    apt-get update

    apt-get install -y \
      docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin

    systemctl enable docker || true
    systemctl start docker || true

    echo " Docker installed successfully"
fi

# ---------------------------------------------------
# 2. Check & Install NVIDIA Container Toolkit
# ---------------------------------------------------
# `dpkg -l | grep` matches a package that was REMOVED: dpkg keeps listing it as
# "rc" (deinstall ok config-files). That made this script report "already
# installed. Skipping..." on a machine with no nvidia-ctk at all, and the
# verification below then printed MISSING in the same run. Test the binary and
# the actual install state instead.
if command -v nvidia-ctk >/dev/null 2>&1 \
   && dpkg-query -W -f='${Status}\n' nvidia-container-toolkit 2>/dev/null | grep -q '^install ok installed'; then
    echo " NVIDIA Container Toolkit already installed. Skipping..."
else
    echo "[2/5] Installing NVIDIA Container Toolkit..."

    apt-get update
    apt-get install -y ca-certificates curl gnupg2

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
      gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
      tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list

    apt-get update

    # NOT version-pinned. Pinning to 1.19.0-1 aborted the whole install on a
    # machine that already had a NEWER libnvidia-container1, because apt treats
    # that as a downgrade and refuses it under -y:
    #     E: Packages were downgraded and -y was used without --allow-downgrades
    # Nothing then installed, nvidia-ctk was missing, and the configure step
    # below failed with "command not found" while the script still reported
    # success. Letting apt pick the current version keeps every machine on a
    # consistent, self-resolving set.
    if ! apt-get install -y \
      nvidia-container-toolkit \
      nvidia-container-toolkit-base \
      libnvidia-container-tools \
      libnvidia-container1; then
        echo "ERROR: failed to install the NVIDIA Container Toolkit packages."
        echo "       Fix the apt error above and run this script again."
        exit 1
    fi

    # Do not claim success on a missing binary: the configure step is what
    # registers the runtime with Docker, and it cannot run without nvidia-ctk.
    if ! command -v nvidia-ctk >/dev/null 2>&1; then
        echo "ERROR: nvidia-ctk is still not present after installation."
        echo "       The toolkit did not install correctly; see the apt output above."
        exit 1
    fi

    # Configure for Docker
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker

    echo " NVIDIA Toolkit installed & configured"
fi

# ---------------------------------------------------
# 3. Check & Install socat
# ---------------------------------------------------
echo "[3/5] Checking socat..."

if command -v socat >/dev/null 2>&1; then
    echo "socat already installed. Skipping..."
else
    echo "Installing socat..."
    apt-get update
    apt-get install -y socat
    echo "socat installed"
fi

# ---------------------------------------------------
# 4. Add user to docker group
# ---------------------------------------------------
echo "[4/5] Configuring Docker permissions..."

TARGET_USER=${SUDO_USER:-$USER}
GROUP_CHANGED=0

if id -nG "$TARGET_USER" | grep -qw docker; then
    echo "User '$TARGET_USER' is already in docker group"
else
    usermod -aG docker "$TARGET_USER"
    GROUP_CHANGED=1
    echo "User '$TARGET_USER' added to docker group"
fi

# ---------------------------------------------------
# 5. Verification
# ---------------------------------------------------
echo "[5/5] Verifying setup..."
VERIFY_FAILED=0

# Check docker binary
if command -v docker >/dev/null 2>&1; then
    echo "Docker binary: OK"
else
    echo "Docker binary: MISSING"; VERIFY_FAILED=1
fi

# Check daemon
if systemctl is-active --quiet docker; then
    echo "Docker service: RUNNING"
else
    echo "Docker service: NOT RUNNING"; VERIFY_FAILED=1
fi

# Check socket
if [ -S /var/run/docker.sock ]; then
    echo "Docker socket: PRESENT"
    ls -l /var/run/docker.sock
else
    echo "Docker socket: MISSING"; VERIFY_FAILED=1
fi

# Verify group membership
if id -nG "$TARGET_USER" | grep -qw docker; then
    echo "Docker group membership for '$TARGET_USER': OK"
else
    echo "Docker group membership for '$TARGET_USER': MISSING"; VERIFY_FAILED=1
fi

# NVIDIA Toolkit Verification

# Check if nvidia-ctk exists
if command -v nvidia-ctk >/dev/null 2>&1; then
    echo "NVIDIA Container Toolkit binary: OK"
else
    echo "NVIDIA Container Toolkit binary: MISSING"; VERIFY_FAILED=1
fi

# Check if docker has nvidia runtime configured
if docker info 2>/dev/null | grep -q "nvidia"; then
    echo "Docker NVIDIA runtime: CONFIGURED"
else
    echo "Docker NVIDIA runtime: NOT CONFIGURED"; VERIFY_FAILED=1
fi

if [ "$VERIFY_FAILED" -ne 0 ]; then
    echo ""
    echo "SETUP INCOMPLETE: one or more checks above reported MISSING."
    echo "PipeGen will not start until they are resolved. See $LOG"
    echo "==== Setup Failed: $(date) ===="
    exit 1
fi

echo "==== Setup Completed: $(date) ===="
echo ""

# ---------------------------------------------------
# 6. Reboot notice (for docker group to take effect)
# ---------------------------------------------------
if [ "$GROUP_CHANGED" -eq 1 ]; then
    echo "----------------------------------------------------------------"
    echo "User '$TARGET_USER' was added to the 'docker' group."
    echo "Please REBOOT (or log out and back in) for this to take effect,"
    echo "so Docker can be run without sudo."
    echo "----------------------------------------------------------------"
else
    echo "No group changes made. No reboot required."
fi
