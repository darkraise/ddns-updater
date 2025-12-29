# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A minimal, security-focused Docker service that automatically updates Cloudflare DNS records when your public IP changes. The entire application is a single shell script (`ddns-updater.sh`) running in an Alpine Linux container.

## Core Architecture

**Single-script design**: The entire DDNS updater logic lives in `ddns-updater.sh` (~290 lines). This is not a multi-component application - it's a stateless shell script that runs in an infinite loop.

**Key components**:
- **IP Detection**: Queries public IP services (ipify.org, ifconfig.me, icanhazip.com) with fallback logic
- **Cloudflare API Integration**: Direct API calls using `wget` (no SDK dependencies)
- **Notification System**: Optional multi-provider notifications (ntfy.sh, Discord, Telegram, Slack, Mailjet)
- **State Management**: Minimal - only tracks current DNS IP vs current public IP (no persistent storage beyond tmpfs)

**Security model**:
- Runs as non-root user (UID 1000)
- Read-only root filesystem with 1MB tmpfs for `/tmp`
- No exposed network ports
- Minimal attack surface (only `wget` and shell built-ins)

## Development Commands

### Local Testing
```bash
# Build the Docker image locally
docker build -t ddns-updater .

# Run with environment file
docker run -d --name ddns-updater --env-file .env ddns-updater

# View logs
docker logs -f ddns-updater

# Stop and remove
docker stop ddns-updater && docker rm ddns-updater
```

### Using Docker Compose
```bash
# Start service
docker-compose up -d

# View logs (tail mode)
docker-compose logs -f

# Stop service
docker-compose down

# Rebuild and restart
docker-compose up -d --build
```

### Testing the Script Directly
```bash
# Run the script locally (requires environment variables)
export CF_API_TOKEN="your_token"
export CF_ZONE_ID="your_zone_id"
export CF_RECORD_NAME="ddns.example.com"
./ddns-updater.sh
```

## Configuration

**Required environment variables** (in `.env`):
- `CF_API_TOKEN` - Cloudflare API token with Zone.DNS (Edit) permission
- `CF_ZONE_ID` - Cloudflare zone identifier
- `CF_RECORD_NAME` - Full DNS record name (e.g., `ddns.example.com`)

**Optional configuration**:
- `CHECK_INTERVAL` (default: 300) - Seconds between IP checks
- `DNS_RECORD_TYPE` (default: A) - Record type (A for IPv4, AAAA for IPv6)
- `DNS_TTL` (default: 120) - TTL in seconds (60-86400)
- `DNS_PROXIED` (default: false) - Cloudflare proxy status (true/false)

**Notification providers** (all optional):
- ntfy.sh: `NTFY_TOPIC`
- Discord: `DISCORD_WEBHOOK`
- Telegram: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
- Slack: `SLACK_WEBHOOK`
- Mailjet: `MAILJET_API_KEY`, `MAILJET_API_SECRET`, `MAILJET_FROM_EMAIL`, `MAILJET_TO_EMAIL`, `MAILJET_FROM_NAME`

## CI/CD Pipeline

Automated builds via GitHub Actions (`.github/workflows/docker-publish.yml`):

**Trigger**: Every push to `master` or manual workflow dispatch

**Process**:
1. Semantic versioning using commit messages:
   - Default: patch bump (v0.0.1 → v0.0.2)
   - `(MINOR)` in commit: minor bump (v0.0.1 → v0.1.0)
   - `(MAJOR)` in commit: major bump (v0.0.1 → v1.0.0)
2. Builds Docker image with layer caching
3. Pushes to two registries:
   - Docker Hub (public): `darkraise/ddns-updater`
   - Vultr Container Registry (private, requires secrets)
4. Tags both `vX.Y.Z` and `latest`
5. Creates and pushes git tag

**Required secrets** (for CI/CD):
- `DOCKERHUB_USERNAME` - Docker Hub username
- `DOCKERHUB_TOKEN` - Docker Hub access token
- `VULTR_REGISTRY_BASE`
- `VULTR_REGISTRY_USERNAME`
- `VULTR_REGISTRY_PASSWORD`

## Code Structure

This is a **shell script project**, not a traditional software application:

**ddns-updater.sh** - Main script with distinct sections:
- Configuration loading (lines 8-20)
- IP detection with fallback (lines 26-35)
- Cloudflare API validation (lines 37-78)
- DNS record retrieval (lines 80-108)
- DNS record update/create (lines 110-158)
- Notification functions (lines 160-232)
- Main check logic (lines 234-274)
- Main loop (lines 276-291)

**Dockerfile** - Multi-stage minimization:
- Base: Alpine 3.20
- Installs only `ca-certificates` (wget is busybox built-in)
- Creates non-root user
- Copies script with executable permissions

**compose.yml** - Production-ready configuration with security hardening

## Important Implementation Notes

### API Error Handling Pattern
The script uses a consistent pattern for Cloudflare API calls:
1. Make request with `wget -qO-`
2. Check if response is empty (network failure)
3. Check HTTP status codes in wget stderr output
4. Check `"success":false` in JSON response
5. Extract data using `grep -o` and `cut` (no jq dependency)

### Notification System
All notification functions follow the same pattern:
- Check if credentials are set, return 0 if not (silent skip)
- Log notification attempt
- Send notification (failures logged but don't stop execution)
- Return 0 regardless of success (non-blocking)

### IP Detection Strategy
Tries multiple services in sequence until one returns a valid IPv4 address. This provides resilience against individual service failures.

### State Management
No persistent database or file storage - compares current public IP against current DNS record IP on each check cycle. The `/tmp` directory is ephemeral (tmpfs).

## Testing Considerations

When testing changes:
1. Use `.env.example` as template, never commit actual `.env`
2. Test API validation by intentionally using bad credentials
3. Test notification systems independently (they're non-blocking)
4. Verify Docker security options (read-only filesystem, non-root user)
5. Check that the script handles API failures gracefully and retries

## Docker Image Distribution

**Public access**: Use `darkraise/ddns-updater:latest` from Docker Hub (no authentication required)

**Private registry**: Vultr registry requires authentication (credentials in GitHub secrets)

Images are built automatically on every push to master, so local builds are only needed for testing changes before committing.
