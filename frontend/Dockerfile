FROM ubuntu:22.04 AS build

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Flutter
RUN git clone https://github.com/flutter/flutter.git -b stable --depth 1 /flutter
ENV PATH="$PATH:/flutter/bin"

# Pre-download dependencies
RUN flutter precache
RUN flutter config --enable-web

WORKDIR /app

# Create non-root user
RUN useradd -m -s /bin/bash nonroot
RUN chown -R nonroot:nonroot /flutter /app
USER nonroot

# Copy pubspec files
COPY --chown=nonroot:nonroot pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy app and build
COPY --chown=nonroot:nonroot . .
RUN flutter build web --release

# Production stage
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80