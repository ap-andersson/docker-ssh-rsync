# SSH/Rsync Container

This container provides a secure SSH server with Rsync and SFTP capabilities, designed for secure file transfers and backups.

## Features
- OpenSSH Server with SFTP and Rsync support.
- Key-based authentication (Password authentication is disabled).
- Automatic generation of SSH host keys and client key pairs.
- Configurable user UID/GID for correct file permissions.
- **Security Hardened**: TCP forwarding, X11 forwarding, and Agent forwarding are disabled by default.
- **Startup Checks**: Validates permissions on mounted data volumes.

## Environment Variables

The container is configured using the following environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `USERNAME` | `admin` | The username for the SSH user inside the container. |
| `PUID` | `1000` | The User ID (UID) to run the user as. **Cannot be 0 (root).** |
| `PGID` | `1000` | The Group ID (GID) to run the user as. **Cannot be 0 (root).** |
| `PASSWORD_ACCESS` | `false` | Set to `true` to enable password login (default is key-only). |
| `USER_PASSWORD` | *None* | Optional. Set a specific password. If `PASSWORD_ACCESS=true` and this is empty, a random one is generated. |

## Volumes

- `/config`: Stores SSH host keys and the generated client key pair (`user_ed25519`).
- `/home/{USERNAME}`: The user's home directory. Mount your data subdirectories here (e.g., `/home/admin/data`).

## Getting Started

1.  Copy `docker-compose.yml.example` to `docker-compose.yml`.
2.  Copy `.env.example` to `.env` and configure your desired settings (User, Port, PUID/PGID).
3.  Run `docker-compose up -d`.

## Client Keys

On the first run, if no client key exists, a new Ed25519 key pair is generated in `/config`:
- **Private Key**: `user_ed25519` (Copy this file to your client to connect).
- **Public Key**: `user_ed25519.pub` (Automatically added to the container's authorized keys).

## Troubleshooting

- **Permission Denied**: If you see permission warnings in the logs, ensure the mounted host directories are owned by the PUID/PGID specified in your `.env` file.
- **Read-Only**: The default example mounts volumes as read-only (`:ro`). Remove `:ro` in `docker-compose.yml` if you need to upload files to the server.
