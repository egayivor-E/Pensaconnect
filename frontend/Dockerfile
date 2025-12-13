# Use the correct Flutter Docker image
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Best Practice: Run build steps as a non-root user
RUN useradd -m --shell /bin/bash nonroot
# In this image, Flutter is installed at /flutter
RUN chown -R nonroot:nonroot /flutter
RUN chown -R nonroot:nonroot /app
ENV HOME /home/nonroot
USER nonroot

# Copy pubspec files first for better layer caching
COPY pubspec.yaml pubspec.lock ./

# Keep the suppress flag for robustness
RUN flutter pub get --suppress-analytics

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
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

EXPOSE 80