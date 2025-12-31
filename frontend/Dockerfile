# Use Flutter Docker image
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Copy pubspec files first for better layer caching
COPY pubspec.yaml pubspec.lock ./

# Get dependencies
RUN flutter pub get --suppress-analytics

# Copy the rest of the code
COPY . .

# Build for web with optimizations
RUN flutter build web --release \
    --dart-define=BACKEND_URL=${BACKEND_URL:https://pensaconnect-pjz9.onrender.com} \
    --pwa-strategy offline-first \
    --source-maps \
    --no-tree-shake-icons

# ----------------------------------------------------
# Production Stage (NGINX)
# ----------------------------------------------------
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80
