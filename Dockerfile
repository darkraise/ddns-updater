# Use Alpine Linux as base - minimal image
FROM alpine:3.20

# Install only ca-certificates (wget is built into busybox)
# Combine all operations in single layer to minimize size
RUN apk add --no-cache ca-certificates && \
    adduser -D -u 1000 ddns

# Copy script with correct permissions in one step
COPY --chmod=755 ddns-updater.sh /usr/local/bin/ddns-updater.sh

# Run as non-root user for security
USER ddns

# Run the updater script
CMD ["/usr/local/bin/ddns-updater.sh"]
