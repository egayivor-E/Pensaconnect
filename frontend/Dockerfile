# Use Flutter Docker image
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Copy pubspec files first for better layer caching
COPY pubspec.yaml pubspec.lock ./

# Get dependencies
RUN flutter pub get --suppress-analytics

# Copy the rest of the code
COPY . .

<<<<<<< HEAD
# Copy .env file from frontend/assets to assets directory
RUN mkdir -p assets && \
    cp frontend/assets/.env assets/.env || echo ".env file not found, creating default" && \
    echo "BACKEND_URL=https://pensaconnect-pjz9.onrender.com/" > assets/.env

# Add this line before the build command
RUN flutter pub run build_runner build --delete-conflicting-outputs

RUN flutter clean && \
    flutter pub get && \
    flutter build web --release \
        --dart-define=BACKEND_URL=https://pensaconnect-pjz9.onrender.com/ \
        --no-tree-shake-icons \
        --no-wasm \
        --verbose
=======
# Use environment variable with fallback
ARG BACKEND_URL=https://pensaconnect-pjz9.onrender.com
ENV BACKEND_URL=${BACKEND_URL}

# Single build command with all necessary flags
RUN flutter build web --release \
    --dart-define=BACKEND_URL=${BACKEND_URL} \
    --no-tree-shake-icons \
    --no-wasm \
    --pwa-strategy=offline-first \
    --verbose
>>>>>>> 82cd073 (Merge remote changes)

# ----------------------------------------------------
# Production Stage (NGINX)
# ----------------------------------------------------
FROM nginx:alpine

# Copy built web files
COPY --from=build /app/build/web /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80