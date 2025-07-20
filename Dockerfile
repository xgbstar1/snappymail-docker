ARG HOST

FROM node AS base
RUN npm install -g gulp
RUN apt-get update && apt-get install -y php php-zip zip unzip curl

FROM base AS builder
ARG GIT_REF
ARG DEBUG=false
WORKDIR /source

# Debug output
RUN if [ "$DEBUG" = "true" ]; then \
        echo "=== BUILD CONFIGURATION ===" && \
        echo "GIT_REF: ${GIT_REF}" && \
        echo "DEBUG: ${DEBUG}" && \
        echo "==========================="; \
    fi

# Download source
RUN echo "=== DOWNLOADING SOURCE ===" && \
    curl -o /source/master.zip -L https://github.com/the-djmaze/snappymail/archive/refs/${GIT_REF}.zip && \
    unzip /source/master.zip -d /source/ && \
    echo "Download complete"

# Debug: Show what we have
RUN if [ "$DEBUG" = "true" ]; then \
        echo "=== SOURCE STRUCTURE ===" && \
        ls -la /source/ && \
        cd /source/*/ && ls -la; \
    fi

# Install dependencies and build
RUN echo "=== INSTALLING DEPENDENCIES ===" && \
    cd /source/*/ && \
    yarn install && \
    echo "Dependencies installed"

# Apply the cross-device link fix (improved version)
RUN echo "=== APPLYING RELEASE.PHP FIX ===" && \
    cd /source/*/ && \
    sed -i 's_^if.*rename.*snappymail.v.0.0.0.*$_if (!!system("cp -r snappymail/v/0.0.0 snappymail/v/{$package->version} && rm -rf snappymail/v/0.0.0")) {_' release.php || true && \
    echo "Fix applied"

# Run the release build
RUN echo "=== BUILDING RELEASE ===" && \
    cd /source/*/ && \
    php release.php && \
    echo "Release build complete"

# Debug: Check what was built
RUN if [ "$DEBUG" = "true" ]; then \
        echo "=== BUILD RESULTS ===" && \
        cd /source/*/ && \
        find . -name "*.zip" -o -name "*.tar.gz" | head -10 && \
        ls -la build/dist/releases/webmail/ || echo "No webmail releases found"; \
    fi

# Extract version and copy artifact
RUN echo "=== EXTRACTING RELEASE ARTIFACT ===" && \
    cd /source/*/ && \
    if [ -d "build/dist/releases/webmail" ]; then \
        ls build/dist/releases/webmail/ > /version && \
        VERSION=$(cat /version) && \
        echo "Found version: $VERSION" && \
        if [ -f "build/dist/releases/webmail/$VERSION/snappymail-$VERSION.zip" ]; then \
            cp "build/dist/releases/webmail/$VERSION/snappymail-$VERSION.zip" /build-stage-artifact && \
            echo "Copied zip artifact"; \
        elif [ -f "build/dist/releases/webmail/$VERSION/snappymail-$VERSION.tar.gz" ]; then \
            cp "build/dist/releases/webmail/$VERSION/snappymail-$VERSION.tar.gz" /build-stage-artifact && \
            echo "Copied tar.gz artifact"; \
        else \
            echo "ERROR: No release archive found for version $VERSION" && \
            ls -la "build/dist/releases/webmail/$VERSION/" && \
            exit 1; \
        fi; \
    else \
        echo "ERROR: No webmail releases directory found" && \
        find . -name "*snappymail*" -type f | head -10 && \
        exit 1; \
    fi

# Verify artifact exists
RUN ls -la /build-stage-artifact && echo "Artifact verification: OK"

FROM php:8.2-apache

# Install basic PHP extensions that SnappyMail needs
RUN apt-get update && apt-get install -y \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libzip-dev \
        unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd zip pdo_mysql opcache \
    && rm -rf /var/lib/apt/lists/*

# Copy your configuration files
COPY ./snappymail.conf /etc/apache2/sites-available/snappymail.conf
COPY ./mail.example.com.pem /etc/certs/mail.example.com.pem

# Copy build artifacts
COPY --from=builder /version /version
COPY --from=builder /build-stage-artifact /build-stage-artifact

# Install SnappyMail
RUN echo "=== INSTALLING SNAPPYMAIL ===" && \
    export VERSION=$(cat /version) && \
    echo "Installing version: $VERSION" && \
    cp /build-stage-artifact /snappymail-$VERSION.archive && \
    \
    # Handle both zip and tar.gz files
    if file /snappymail-$VERSION.archive | grep -q "Zip"; then \
        echo "Extracting ZIP archive..." && \
        unzip -o /snappymail-$VERSION.archive -d /var/www/snappymail; \
    elif file /snappymail-$VERSION.archive | grep -q "gzip"; then \
        echo "Extracting TAR.GZ archive..." && \
        mkdir -p /var/www/snappymail && \
        tar -xzf /snappymail-$VERSION.archive -C /var/www/snappymail; \
    else \
        echo "ERROR: Unknown archive format" && \
        file /snappymail-$VERSION.archive && \
        exit 1; \
    fi && \
    \
    echo "=== INSTALLATION VERIFICATION ===" && \
    ls -la /var/www/snappymail/ && \
    \
    # Clean up
    rm -f /build-stage-artifact /snappymail-$VERSION.archive && \
    echo "Installation complete"

# Optional: Add CSS customizations (keeping your original feature)
# COPY css-customizations/customizations.css /tmp/customizations.css
# RUN export VERSION=$(cat /version) && \
#     if [ -f "/tmp/customizations.css" ]; then \
#         echo "=== APPLYING CSS CUSTOMIZATIONS ===" && \
#         find /var/www/snappymail -name "app.min.css" -exec cat /tmp/customizations.css >> {} \; && \
#         rm /tmp/customizations.css && \
#         echo "CSS customizations applied"; \
#     fi

# Set permissions and configure Apache
RUN chown -R www-data:www-data /var/www/snappymail/ && \
    a2ensite snappymail.conf && \
    a2enmod rewrite ssl

# Clean up
RUN rm -f /version

WORKDIR /var/www/snappymail

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

EXPOSE 80 443
