#!/usr/bin/env bash
# hsftp installer
# Usage:
#   curl -s https://raw.githubusercontent.com/MaxDevv/personal-hsftp/main/install.sh | bash -s -- PASSWORD
#
# What this does:
#   1. Downloads hsftp.enc from the same repo
#   2. Decrypts it with the password you pass
#   3. Installs into ~/.hsftp/ with its own venv
#   4. Creates the `hsftp` command in /usr/local/bin (or ~/.local/bin if no sudo)

set -e

# ── Config ────────────────────────────────────────────────────────────────────

REPO_RAW="https://raw.githubusercontent.com/MaxDevv/personal-hsftp/main"
INSTALL_DIR="$HOME/.hsftp"
ENC_URL="$REPO_RAW/hsftp.enc"
CMD_NAME="hsftp"

# ── Password ──────────────────────────────────────────────────────────────────

PASS="${1:-}"
if [ -z "$PASS" ]; then
    echo "Usage: curl -s $REPO_RAW/install.sh | bash -s -- PASSWORD"
    exit 1
fi

# ── Dependency check ──────────────────────────────────────────────────────────

for dep in openssl python3 curl; do
    if ! command -v "$dep" &>/dev/null; then
        echo "Error: '$dep' is required but not found."
        exit 1
    fi
done

# ── Download & decrypt ────────────────────────────────────────────────────────

echo "==> Downloading encrypted script..."
TMP_ENC="$(mktemp /tmp/hsftp.enc.XXXXXX)"
curl -fsSL "$ENC_URL" -o "$TMP_ENC"

echo "==> Decrypting..."
TMP_PY="$(mktemp /tmp/hsftp.py.XXXXXX)"
if ! openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -d \
        -in "$TMP_ENC" -out "$TMP_PY" -pass pass:"$PASS" 2>/dev/null; then
    echo "Error: decryption failed — wrong password?"
    rm -f "$TMP_ENC" "$TMP_PY"
    exit 1
fi
rm -f "$TMP_ENC"

# Quick sanity check — should look like a Python script
if ! head -1 "$TMP_PY" | grep -q "python"; then
    echo "Error: decrypted file doesn't look right."
    rm -f "$TMP_PY"
    exit 1
fi

# ── Install directory + venv ──────────────────────────────────────────────────

echo "==> Setting up $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
cp "$TMP_PY" "$INSTALL_DIR/hsftp.py"
chmod 600 "$INSTALL_DIR/hsftp.py"   # credentials are in here
rm -f "$TMP_PY"

echo "==> Creating Python venv..."
# On Debian/Ubuntu, python3-venv is a separate package that's often missing
if ! python3 -m venv --help &>/dev/null || ! python3 -c "import ensurepip" &>/dev/null; then
    echo "    python3-venv not found — installing..."
    if command -v apt-get &>/dev/null; then
            PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
            apt-get update -qq
            apt-get install -y -qq "python3.${PY_VER##*.}-venv" 2>/dev/null || \
            apt-get install -y -qq python3-venv
    elif command -v dnf &>/dev/null; then
        dnf install -y -q python3 python3-pip
    elif command -v yum &>/dev/null; then
        yum install -y -q python3 python3-pip
    fi
fi
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install --quiet paramiko

# ── Wrapper script ────────────────────────────────────────────────────────────

WRAPPER="$INSTALL_DIR/$CMD_NAME"
cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
exec "$INSTALL_DIR/venv/bin/python3" "$INSTALL_DIR/hsftp.py" "\$@"
EOF
chmod 755 "$WRAPPER"

# ── Symlink into PATH ─────────────────────────────────────────────────────────

SYSTEM_BIN="/usr/local/bin/$CMD_NAME"
LOCAL_BIN="$HOME/.local/bin/$CMD_NAME"

if [ -w /usr/local/bin ]; then
    ln -sf "$WRAPPER" "$SYSTEM_BIN"
    echo "==> Linked: $SYSTEM_BIN"
elif sudo -n true 2>/dev/null; then
    sudo ln -sf "$WRAPPER" "$SYSTEM_BIN"
    echo "==> Linked (sudo): $SYSTEM_BIN"
else
    mkdir -p "$HOME/.local/bin"
    ln -sf "$WRAPPER" "$LOCAL_BIN"
    echo "==> Linked: $LOCAL_BIN"
    # Make sure ~/.local/bin is on PATH for future sessions
    SHELL_RC="$HOME/.bashrc"
    if [ -n "$ZSH_VERSION" ] || echo "$SHELL" | grep -q zsh; then
        SHELL_RC="$HOME/.zshrc"
    fi
    if ! grep -q '\.local/bin' "$SHELL_RC" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
        echo "==> Added ~/.local/bin to PATH in $SHELL_RC"
    fi
    export PATH="$HOME/.local/bin:$PATH"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "✓ hsftp installed.  Run:  hsftp"
echo ""
