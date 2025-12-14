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

### Using Pre-built Docker Image

The easiest way to get started is using a pre-built image. Images are available from GitHub Container Registry (public)

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env with your Cloudflare credentials
nano .env

# Pull and run the latest image
docker run -d \
  --name ddns-updater \
  --restart unless-stopped \
  --env-file .env \
  ghcr.io/darkraise/ddns-updater:latest
```

**Using Docker Compose:**

Update `compose.yml` to use the pre-built image:

```yaml
services:
  ddns-updater:
    image: ghcr.io/darkraise/ddns-updater:latest
    # ... rest of your config
```

### Building from Source

If you prefer to build locally:

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

### Required Variables

| Variable         | Description                                    |
| ---------------- | ---------------------------------------------- |
| `CF_API_TOKEN`   | Cloudflare API token with DNS edit permissions |
| `CF_ZONE_ID`     | Cloudflare zone ID for your domain             |
| `CF_RECORD_NAME` | Full DNS record name (e.g., ddns.example.com)  |

### Optional - Basic Configuration

| Variable          | Default | Description                                                       |
| ----------------- | ------- | ----------------------------------------------------------------- |
| `CHECK_INTERVAL`  | 300     | Interval in seconds between IP checks                             |
| `DNS_RECORD_TYPE` | A       | DNS record type (A for IPv4, AAAA for IPv6)                       |
| `DNS_TTL`         | 120     | Time to live in seconds (60-86400, or 1 for auto)                 |
| `DNS_PROXIED`     | false   | Cloudflare proxy status (true = orange cloud, false = gray cloud) |

### Optional - Notification Services

Configure one or more notification services to receive alerts when your IP address changes:

| Service      | Variables                                                                                                                 | Description                                 |
| ------------ | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| **ntfy.sh**  | `NTFY_TOPIC`                                                                                                              | Free push notifications, no signup required |
| **Discord**  | `DISCORD_WEBHOOK`                                                                                                         | Send notifications to Discord channel       |
| **Telegram** | `TELEGRAM_BOT_TOKEN`<br>`TELEGRAM_CHAT_ID`                                                                                | Bot notifications via Telegram              |
| **Slack**    | `SLACK_WEBHOOK`                                                                                                           | Send notifications to Slack channel         |
| **Mailjet**  | `MAILJET_API_KEY`<br>`MAILJET_API_SECRET`<br>`MAILJET_FROM_EMAIL`<br>`MAILJET_TO_EMAIL`<br>`MAILJET_FROM_NAME` (optional) | Email notifications via Mailjet API         |

See `.env.example` for detailed setup instructions for each notification service.

### Configuration Examples

**Check Interval:**

- `60` - Check every 1 minute (frequent updates)
- `300` - Check every 5 minutes (recommended)
- `600` - Check every 10 minutes
- `3600` - Check every 1 hour (infrequent changes)

**DNS Proxied:**

- `false` - DNS only (gray cloud) - Recommended for DDNS
- `true` - Proxied through Cloudflare (orange cloud) - Hides real IP

## Manual Docker Run

If you prefer not to use Docker Compose:

```bash
# Build the image
docker build -t ddns-updater .

# Run the container
docker run -d \
  --name ddns-updater \
  --restart unless-stopped \
  -e CF_API_TOKEN=your_token \
  -e CF_ZONE_ID=your_zone_id \
  -e CF_RECORD_NAME=ddns.example.com \
  -e CHECK_INTERVAL=300 \
  ddns-updater
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
docker-compose logs -f ddns-updater

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
docker ps | grep ddns-updater
```

### View recent logs

```bash
docker-compose logs --tail=50 ddns-updater
```

### Test IP detection manually

```bash
docker-compose exec ddns-updater wget -qO- https://api.ipify.org
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

- **Image size**: ~14 MB
- **Memory usage**: 10-20 MB
- **CPU usage**: <1% (mostly idle)
- **Network**: Minimal (~1KB per check)

## Security Features

- Runs as non-root user (UID 1000)
- Read-only root filesystem
- Minimal attack surface (only wget and sh)
- No exposed network ports
- API token never logged or exposed

## Docker Images

Pre-built Docker images are automatically built and published via GitHub Actions on every push to master.

### Available Registries

Images are published to two registries:

1. **GitHub Container Registry (Public)**: `ghcr.io/darkraise/ddns-updater`
   - Publicly accessible
   - No authentication required for pulling
   - Recommended for most users

### Available Tags

- `latest` - Latest build from master branch
- `vX.Y.Z` - Specific semantic versions (e.g., `v0.0.1`, `v0.1.0`)

### Automated Builds

- Every push to master triggers a new build
- Images are published to both registries simultaneously
- Versions are automatically incremented using semantic versioning
- Both version-specific and `latest` tags are updated
- Builds include Docker layer caching for faster deployments

## Development

### CI/CD Workflow

The project uses GitHub Actions to automatically:

1. Build the Docker image on every push to master
2. Increment the version number automatically
3. Push to GitHub Container Registry (ghcr.io)
4. Tag images with both version-specific tags and `latest`
5. Create git tags for version tracking

### Version Bumping

Versions are automatically incremented by default (patch version):

- **Patch** (default): `v0.0.1` → `v0.0.2`
- **Minor**: Include `(MINOR)` in commit message → `v0.0.1` → `v0.1.0`
- **Major**: Include `(MAJOR)` in commit message → `v0.0.1` → `v1.0.0`

## License

MIT License - feel free to use and modify as needed.
