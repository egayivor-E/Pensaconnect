# Use a specific, recent tag of Flutter that includes Dart SDK >= 3.8.1
# Example: Using 3.22.0 which uses a recent Dart version (check the cirrusci tags for the absolute latest if 3.22.0 is not sufficient)
FROM cirrusci/flutter:latest AS build
# ----------------------------------------------------
# Secure Build Stage
# ----------------------------------------------------
WORKDIR /app

# Best Practice: Run build steps as a non-root user
RUN adduser -D nonroot
RUN chown -R nonroot:nonroot /app
USER nonroot

# Copy pubspec files first for better layer caching
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy the rest of the code
COPY . .

# Build for web with optimizations
RUN flutter build web --release \
    --web-renderer canvaskit \
    --dart-define=BACKEND_URL=${BACKEND_URL:-https://pensaconnect.onrender.com} \
    --pwa-strategy offline-first \
    --source-maps

# ----------------------------------------------------
# Production Stage (NGINX)
# ----------------------------------------------------
# Nginx is a great choice for serving static Flutter web builds.
FROM nginx:alpine

# Copy built web files from the 'build' stage
# NGINX runs as a non-root user (nginx) in the alpine image, so no further user change is needed here.
COPY --from=build /app/build/web /usr/share/nginx/html

# Add custom nginx configuration for SPA routing
COPY nginx.conf /etc/nginx/nginx.conf

# Health check (optional but recommended)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

EXPOSE 80