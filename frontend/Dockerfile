# Use Flutter Docker image
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Copy pubspec files first for better layer caching
COPY pubspec.yaml pubspec.lock ./

# Get dependencies
RUN flutter pub get --suppress-analytics

# Copy the rest of the code
COPY . .

# Add this line before the build command
RUN flutter pub run build_runner build --delete-conflicting-outputs

RUN flutter clean && \
    flutter pub get && \
    flutter build web --release \
        --dart-define=BACKEND_URL=$BACKEND_URL \
        --no-tree-shake-icons \
        --verbose

# ----------------------------------------------------
# Production Stage (NGINX)
# ----------------------------------------------------
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80
