#!/bin/bash
set -e

# --- CONFIG VARIABLES ---
# Set default values for user, PUID, and PGID if not provided
USERNAME=${USERNAME:-admin}
PUID=${PUID:-1000}
PGID=${PGID:-1000}
CONFIG_DIR="/config"
HOST_KEY_DIR="$CONFIG_DIR/ssh_host_keys"
USER_KEY_DIR="/home/$USERNAME/.ssh"

# --- SAFETY CHECK ---
if [ "$PUID" -eq 0 ] || [ "$PGID" -eq 0 ]; then
    echo "Error: PUID and PGID cannot be 0 (root). Please use a non-root user."
    exit 1
fi

# --- USER & GROUP SETUP ---
# Check if a group with the specified PGID exists
GROUPNAME=$(getent group "$PGID" | cut -d: -f1 || true)
if [ -z "$GROUPNAME" ]; then
    echo "Creating group $USERNAME with GID $PGID"
    addgroup -g "$PGID" "$USERNAME"
elif [ "$GROUPNAME" != "$USERNAME" ]; then
    # If it exists but has a different name, rename it (or delete and recreate)
    echo "Group with GID $PGID ($GROUPNAME) exists, renaming to $USERNAME..."
    delgroup "$GROUPNAME"
    addgroup -g "$PGID" "$USERNAME"
fi

# Check if a user with the specified PUID exists
USERNAME_FROM_UID=$(getent passwd "$PUID" | cut -d: -f1 || true)
if [ -z "$USERNAME_FROM_UID" ]; then
    echo "Creating user $USERNAME with UID $PUID"
    adduser -D -H -s /bin/bash -u "$PUID" -G "$USERNAME" -h "/home/$USERNAME" "$USERNAME"
elif [ "$USERNAME_FROM_UID" != "$USERNAME" ]; then
    # If it exists but has a different name, recreate it
    echo "User with UID $PUID ($USERNAME_FROM_UID) exists, recreating as $USERNAME..."
    deluser "$USERNAME_FROM_UID"
    adduser -D -H -s /bin/bash -u "$PUID" -G "$USERNAME" -h "/home/$USERNAME" "$USERNAME"
fi

# Ensure home directory exists and has correct permissions
mkdir -p "/home/$USERNAME"
chown "$USERNAME:$USERNAME" "/home/$USERNAME"
chmod 750 "/home/$USERNAME"

# Set a random password for the user to unlock the account
echo "$USERNAME:$(date +%s | sha256sum | base64 | head -c 32)" | chpasswd

# --- SSH CONFIGURATION ---
echo "Configuring SSH access for user $USERNAME..."
echo "" >> /etc/ssh/sshd_config
# Remove existing AllowUsers directive and add the current user
sed -i '/^AllowUsers/d' /etc/ssh/sshd_config
echo "AllowUsers $USERNAME" >> /etc/ssh/sshd_config

# --- SETUP HOST KEYS ---
# Host keys identify the server to the client.
mkdir -p "$HOST_KEY_DIR"
chmod 700 "$HOST_KEY_DIR"
if [ ! -f "$HOST_KEY_DIR/ssh_host_rsa_key" ]; then
    echo "Generating RSA host key..."
    ssh-keygen -f "$HOST_KEY_DIR/ssh_host_rsa_key" -N '' -t rsa
else
    echo "RSA host key found."
fi

if [ ! -f "$HOST_KEY_DIR/ssh_host_ed25519_key" ]; then
    echo "Generating Ed25519 host key..."
    ssh-keygen -f "$HOST_KEY_DIR/ssh_host_ed25519_key" -N '' -t ed25519
else
    echo "Ed25519 host key found."
fi

# Set correct permissions for host keys
chown root:root "$HOST_KEY_DIR" "$HOST_KEY_DIR"/*
chmod 600 $HOST_KEY_DIR/*_key
chmod 644 $HOST_KEY_DIR/*.pub


# --- SETUP USER KEYS ---
USER_PUB_KEY_PATH="$CONFIG_DIR/user_ed25519.pub"
USER_PRIV_KEY_PATH="$CONFIG_DIR/user_ed25519"

# Generate a user key pair if one doesn't exist in the config directory
if [ ! -f "$USER_PUB_KEY_PATH" ]; then
    echo "No user public key found at $USER_PUB_KEY_PATH. Generating new key pair..."
    ssh-keygen -f "$USER_PRIV_KEY_PATH" -N "" -t ed25519
    echo "New key pair generated:"
    echo "Public Key: $USER_PUB_KEY_PATH"
    echo "Private Key: $USER_PRIV_KEY_PATH"
    echo "Key Filename: $(basename "$USER_PRIV_KEY_PATH")"
fi

# Install the public key into authorized_keys for the user
mkdir -p "$USER_KEY_DIR"
# Remove carriage returns if present (e.g. from Windows edits)
tr -d '\r' < "$USER_PUB_KEY_PATH" > "$USER_KEY_DIR/authorized_keys"

# Secure the .ssh directory and authorized_keys file
chmod 700 "$USER_KEY_DIR"
chmod 600 "$USER_KEY_DIR/authorized_keys"
chown -R "$USERNAME:$USERNAME" "$USER_KEY_DIR"

# Set correct permissions for user keys in config
chmod 600 "$USER_PRIV_KEY_PATH"
chmod 644 "$USER_PUB_KEY_PATH"
chown $PUID:$PGID "$CONFIG_DIR"/*_ed25519*


# --- START SSH ---
echo "Starting SSH daemon..."

# Check for permission issues on mounted volumes
echo "Checking data directory permissions..."
for dir in "/home/$USERNAME"/*; do
    if [ -d "$dir" ]; then
        # Check if user can read and execute (enter) the directory
        if ! su -s /bin/bash "$USERNAME" -c "test -r '$dir' && test -x '$dir'"; then
            echo "WARNING: User '$USERNAME' (UID $PUID) cannot access '$dir'."
            echo "         This is likely a permission issue on the host volume."
            echo "         Current permissions: $(ls -ld "$dir")"
            echo "         Ensure the host folder is readable by UID $PUID or GID $PGID."
        fi
    fi
done

# Start sshd in non-daemon mode (foreground) and send output to stderr
exec /usr/sbin/sshd -D -e
