#!/bin/sh

# Cloudflare DDNS Updater
# Minimal script to update Cloudflare DNS records when public IP changes

set -e

# Configuration from environment variables
CF_API_TOKEN="${CF_API_TOKEN:?CF_API_TOKEN environment variable is required}"
CF_ZONE_ID="${CF_ZONE_ID:?CF_ZONE_ID environment variable is required}"
CF_RECORD_NAME="${CF_RECORD_NAME:?CF_RECORD_NAME environment variable is required}"
CHECK_INTERVAL="${CHECK_INTERVAL:-300}"  # Default 5 minutes (300 seconds)

# DNS Record Configuration
DNS_RECORD_TYPE="${DNS_RECORD_TYPE:-A}"  # Default: A (IPv4)
DNS_TTL="${DNS_TTL:-120}"  # Default: 120 seconds
DNS_PROXIED="${DNS_PROXIED:-false}"  # Default: false (DNS only)

# Public IP services (will try in order if one fails)
IP_SERVICES="https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

get_public_ip() {
    for service in $IP_SERVICES; do
        ip=$(wget -qO- -T 10 "$service" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$ip" ] && echo "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

validate_cloudflare_access() {
    log "Validating Cloudflare API access..."

    # Test 1: Verify Zone exists and is accessible
    response=$(wget -qO- \
        --header="Authorization: Bearer $CF_API_TOKEN" \
        --header="Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID" 2>&1)

    if [ -z "$response" ]; then
        log "ERROR: Cannot reach Cloudflare API (check network connectivity)"
        return 1
    fi

    # Check for wget HTTP errors in response
    if echo "$response" | grep -q "HTTP request sent, awaiting response... 404"; then
        log "ERROR: Zone ID '$CF_ZONE_ID' not found (HTTP 404)"
        log "Please verify your CF_ZONE_ID in the .env file"
        log "Find it at: https://dash.cloudflare.com/ > Select Domain > Overview (right sidebar)"
        return 1
    fi

    if echo "$response" | grep -qE "HTTP request sent, awaiting response... 40[13]"; then
        log "ERROR: Authentication failed"
        log "Please verify your CF_API_TOKEN has the following permissions:"
        log "  - Zone.DNS (Edit)"
        log "  - Zone.Zone (Read)"
        return 1
    fi

    if echo "$response" | grep -q '"success":false'; then
        error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
        error_code=$(echo "$response" | grep -o '"code":[0-9]*' | head -1 | cut -d':' -f2)
        log "ERROR: Cloudflare API error (code: $error_code): $error_msg"
        return 1
    fi

    zone_name=$(echo "$response" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
    log "✓ Successfully connected to zone: $zone_name"

    return 0
}

get_cloudflare_record() {
    response=$(wget -qO- \
        --header="Authorization: Bearer $CF_API_TOKEN" \
        --header="Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=$CF_RECORD_NAME&type=$DNS_RECORD_TYPE" 2>&1)

    if [ -z "$response" ]; then
        log "ERROR: No response from Cloudflare API (network issue or wget failed)"
        return 1
    fi

    # Check for API errors
    if echo "$response" | grep -q '"success":false'; then
        error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
        log "ERROR: Cloudflare API error: $error_msg"
        return 1
    fi

    # Extract record ID and IP address using simple string manipulation
    record_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    record_ip=$(echo "$response" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -n "$record_id" ]; then
        # Return format: "record_id|record_ip"
        echo "$record_id|$record_ip"
        return 0
    fi
    return 1
}

update_cloudflare_dns() {
    new_ip="$1"
    record_id="$2"

    log "Updating Cloudflare DNS record $CF_RECORD_NAME to $new_ip"

    response=$(wget -qO- --method=PUT \
        --header="Authorization: Bearer $CF_API_TOKEN" \
        --header="Content-Type: application/json" \
        --body-data="{\"type\":\"$DNS_RECORD_TYPE\",\"name\":\"$CF_RECORD_NAME\",\"content\":\"$new_ip\",\"ttl\":$DNS_TTL,\"proxied\":$DNS_PROXIED}" \
        "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$record_id" 2>&1)

    if [ -z "$response" ]; then
        log "ERROR: No response from Cloudflare API (network issue or wget failed)"
        return 1
    fi

    if echo "$response" | grep -q '"success":true'; then
        log "Successfully updated DNS record"
        return 0
    else
        log "Failed to update DNS record. Response: $response"
        return 1
    fi
}

create_cloudflare_dns() {
    new_ip="$1"

    log "Creating Cloudflare DNS record $CF_RECORD_NAME with IP $new_ip"

    response=$(wget -qO- --post-data="{\"type\":\"$DNS_RECORD_TYPE\",\"name\":\"$CF_RECORD_NAME\",\"content\":\"$new_ip\",\"ttl\":$DNS_TTL,\"proxied\":$DNS_PROXIED}" \
        --header="Authorization: Bearer $CF_API_TOKEN" \
        --header="Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" 2>&1)

    if [ -z "$response" ]; then
        log "ERROR: No response from Cloudflare API (network issue or wget failed)"
        return 1
    fi

    if echo "$response" | grep -q '"success":true'; then
        log "Successfully created DNS record"
        return 0
    else
        log "Failed to create DNS record. Response: $response"
        return 1
    fi
}

# Notification Functions
notify_ntfy() {
    [ -z "$NTFY_TOPIC" ] && return 0

    message="$1"
    log "Sending ntfy notification"
    wget -qO- --post-data="$message" \
        --header="Title: DDNS Update" \
        --header="Priority: default" \
        "https://ntfy.sh/$NTFY_TOPIC" >/dev/null 2>&1 || log "Failed to send ntfy notification"
}

notify_discord() {
    [ -z "$DISCORD_WEBHOOK" ] && return 0

    message="$1"
    log "Sending Discord notification"
    wget -qO- --post-data="{\"content\":\"🌐 $message\"}" \
        --header="Content-Type: application/json" \
        "$DISCORD_WEBHOOK" >/dev/null 2>&1 || log "Failed to send Discord notification"
}

notify_telegram() {
    [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ] && return 0

    message="$1"
    # URL encode the message
    encoded_msg=$(echo "$message" | sed 's/ /%20/g' | sed 's/:/\%3A/g')
    log "Sending Telegram notification"
    wget -qO- "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage?chat_id=$TELEGRAM_CHAT_ID&text=$encoded_msg" \
        >/dev/null 2>&1 || log "Failed to send Telegram notification"
}

notify_slack() {
    [ -z "$SLACK_WEBHOOK" ] && return 0

    message="$1"
    log "Sending Slack notification"
    wget -qO- --post-data="{\"text\":\"$message\"}" \
        --header="Content-Type: application/json" \
        "$SLACK_WEBHOOK" >/dev/null 2>&1 || log "Failed to send Slack notification"
}

notify_mailjet() {
    [ -z "$MAILJET_API_KEY" ] || [ -z "$MAILJET_API_SECRET" ] || [ -z "$MAILJET_FROM_EMAIL" ] || [ -z "$MAILJET_TO_EMAIL" ] && return 0

    message="$1"
    from_name="${MAILJET_FROM_NAME:-DDNS Updater}"

    log "Sending Mailjet email notification"

    # Create JSON payload for Mailjet v3.1 API
    json_payload="{\"Messages\":[{\"From\":{\"Email\":\"$MAILJET_FROM_EMAIL\",\"Name\":\"$from_name\"},\"To\":[{\"Email\":\"$MAILJET_TO_EMAIL\"}],\"Subject\":\"DDNS IP Address Updated\",\"TextPart\":\"$message\",\"HTMLPart\":\"<h3>DDNS Update Notification</h3><p>$message</p><p><small>Sent by Cloudflare DDNS Updater at $(date +'%Y-%m-%d %H:%M:%S')</small></p>\"}]}"

    # Mailjet uses Basic Auth with API key and secret (encode as base64)
    auth_header=$(echo -n "$MAILJET_API_KEY:$MAILJET_API_SECRET" | base64)

    wget -qO- --post-data="$json_payload" \
        --header="Content-Type: application/json" \
        --header="Authorization: Basic $auth_header" \
        "https://api.mailjet.com/v3.1/send" >/dev/null 2>&1 || log "Failed to send Mailjet email"
}

send_notifications() {
    message="$1"

    # Send to all configured notification services
    notify_ntfy "$message"
    notify_discord "$message"
    notify_telegram "$message"
    notify_slack "$message"
    notify_mailjet "$message"
}

check_and_update() {
    # Get current public IP
    current_ip=$(get_public_ip)
    if [ -z "$current_ip" ]; then
        log "ERROR: Failed to get public IP from any service"
        return 1
    fi

    log "Current public IP: $current_ip"

    # Get Cloudflare DNS record info
    record_info=$(get_cloudflare_record)

    if [ -n "$record_info" ]; then
        # Parse record ID and IP
        record_id=$(echo "$record_info" | cut -d'|' -f1)
        dns_ip=$(echo "$record_info" | cut -d'|' -f2)

        log "DNS record IP: $dns_ip"

        # Check if IP changed
        if [ "$current_ip" = "$dns_ip" ]; then
            log "IP unchanged, no update needed"
            notify_discord "IP check: $CF_RECORD_NAME still points to $current_ip (no change)"
            return 0
        fi

        log "IP changed from '$dns_ip' to '$current_ip'"

        # Update existing record
        if update_cloudflare_dns "$current_ip" "$record_id"; then
            send_notifications "DNS record $CF_RECORD_NAME updated: $dns_ip -> $current_ip"
        fi
    else
        # Record doesn't exist, create it
        log "DNS record not found, creating new record"
        if create_cloudflare_dns "$current_ip"; then
            send_notifications "DNS record $CF_RECORD_NAME created with IP: $current_ip"
        fi
    fi
}

# Main loop
log "Starting Cloudflare DDNS Updater"
log "Domain: $CF_RECORD_NAME"
log "Check interval: ${CHECK_INTERVAL}s"

# Validate Cloudflare API access before starting
if ! validate_cloudflare_access; then
    log "FATAL: Failed to validate Cloudflare API access. Exiting."
    exit 1
fi

while true; do
    check_and_update || log "Check failed, will retry on next interval"
    log "================================"
    sleep "$CHECK_INTERVAL"
done
