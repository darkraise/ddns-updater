# Cloudflare DDNS Updater

A lightweight, minimal Docker service that automatically updates Cloudflare DNS records when your public IP address changes. Perfect for home servers and dynamic IP environments.

## Features

- **Minimal footprint**: Based on Alpine Linux (~7-8MB final image)
- **Low resource usage**: <32MB RAM, minimal CPU
- **Automatic IP detection**: Checks multiple public IP services
- **Smart updates**: Only updates DNS when IP actually changes
- **Configurable interval**: Set check frequency via environment variable
- **Auto-recovery**: Handles API failures gracefully
- **Secure**: Runs as non-root user with read-only filesystem

## Quick Start

### 1. Get Cloudflare API Token

1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Click "Create Token"
3. Use the "Edit zone DNS" template or create custom token with:
   - Permissions: `Zone.DNS` (Edit)
   - Zone Resources: Include → Specific zone → Your domain
4. Copy the generated token

### 2. Get Zone ID

1. Go to your Cloudflare dashboard
2. Select your domain
3. Scroll down on the Overview page
4. Copy the "Zone ID" from the right sidebar

### 3. Configure Environment

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env with your values
nano .env
```

Required variables in `.env`:
```env
CF_API_TOKEN=your_api_token_here
CF_ZONE_ID=your_zone_id_here
CF_RECORD_NAME=ddns.example.com
CHECK_INTERVAL=300
```

### 4. Run with Docker Compose

```bash
# Build and start the service
docker-compose up -d

# View logs
docker-compose logs -f

# Stop the service
docker-compose down
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CF_API_TOKEN` | Yes | - | Cloudflare API token with DNS edit permissions |
| `CF_ZONE_ID` | Yes | - | Cloudflare zone ID for your domain |
| `CF_RECORD_NAME` | Yes | - | Full DNS record name (e.g., ddns.example.com) |
| `CHECK_INTERVAL` | No | 300 | Interval in seconds between IP checks |

### Check Interval Examples

- `60` - Check every 1 minute (frequent updates)
- `300` - Check every 5 minutes (recommended)
- `600` - Check every 10 minutes
- `3600` - Check every 1 hour (infrequent changes)

## Manual Docker Run

If you prefer not to use Docker Compose:

```bash
# Build the image
docker build -t cloudflare-ddns .

# Run the container
docker run -d \
  --name cloudflare-ddns \
  --restart unless-stopped \
  -e CF_API_TOKEN=your_token \
  -e CF_ZONE_ID=your_zone_id \
  -e CF_RECORD_NAME=ddns.example.com \
  -e CHECK_INTERVAL=300 \
  cloudflare-ddns
```

## How It Works

1. **IP Detection**: Queries public IP services (ipify.org, ifconfig.me, icanhazip.com)
2. **Change Detection**: Compares current IP with last known IP stored in `/tmp/last_ip.txt`
3. **DNS Update**: If IP changed, calls Cloudflare API to update the A record
4. **Repeat**: Sleeps for configured interval and repeats

## Logs

The service logs all operations:

```bash
# View logs
docker-compose logs -f cloudflare-ddns

# Example output
[2025-12-13 10:00:00] Starting Cloudflare DDNS Updater
[2025-12-13 10:00:00] Domain: ddns.example.com
[2025-12-13 10:00:00] Check interval: 300s
[2025-12-13 10:00:01] Current public IP: 203.0.113.45
[2025-12-13 10:00:01] IP changed from '' to '203.0.113.45'
[2025-12-13 10:00:01] Updating Cloudflare DNS record ddns.example.com to 203.0.113.45
[2025-12-13 10:00:02] Successfully updated DNS record
```

## Troubleshooting

### Check if container is running
```bash
docker ps | grep cloudflare-ddns
```

### View recent logs
```bash
docker-compose logs --tail=50 cloudflare-ddns
```

### Test IP detection manually
```bash
docker-compose exec cloudflare-ddns wget -qO- https://api.ipify.org
```

### Common Issues

**"CF_API_TOKEN environment variable is required"**
- Ensure `.env` file exists and contains `CF_API_TOKEN`

**"Failed to get public IP"**
- Check internet connectivity
- Firewall might be blocking outbound HTTPS

**"Failed to update DNS record"**
- Verify API token has correct permissions
- Check Zone ID is correct
- Ensure DNS record name matches exactly

## Resource Usage

Typical resource consumption:
- **Image size**: ~7-8 MB
- **Memory usage**: 10-20 MB
- **CPU usage**: <1% (mostly idle)
- **Network**: Minimal (~1KB per check)

## Security Features

- Runs as non-root user (UID 1000)
- Read-only root filesystem
- Minimal attack surface (only wget and sh)
- No exposed network ports
- API token never logged or exposed

## License

MIT License - feel free to use and modify as needed.
