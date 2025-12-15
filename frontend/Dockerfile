FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Create non-root user
RUN useradd -m --shell /bin/bash nonroot

# Set ownership only on /app (skip /flutter as it's not needed for build)
RUN chown -R nonroot:nonroot /app

# Set environment and switch to non-root user
ENV HOME /home/nonroot
USER nonroot

# Copy pubspec files first for better layer caching
COPY --chown=nonroot:nonroot pubspec.yaml pubspec.lock ./

# Keep the suppress flag for robustness
RUN flutter pub get --suppress-analytics

# Copy the rest of the code
COPY --chown=nonroot:nonroot . .

# Build for web with optimizations
RUN flutter build web --release \
    --web-renderer canvaskit \
    --dart-define=BACKEND_URL=${BACKEND_URL:-https://pensaconnect.onrender.com} \
    --pwa-strategy offline-first \
    --source-maps

# ----------------------------------------------------
# Production Stage (NGINX)
# ----------------------------------------------------
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

EXPOSE 80