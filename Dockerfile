ARG HOST

FROM node AS base
RUN npm install -g gulp
RUN apt-get update && apt-get install -y php php-zip zip unzip curl

FROM base AS builder
ARG GIT_REF
ARG DEBUG=false
WORKDIR /source

# Debug output
RUN echo "=== BUILD CONFIGURATION ===" && \
    echo "GIT_REF: ${GIT_REF}" && \
    echo "DEBUG: ${DEBUG}" && \
    echo "=========================="

# Download and extract source
RUN echo "=== DOWNLOADING SOURCE ===" && \
    curl -o /source/master.zip -L https://github.com/the-djmaze/snappymail/archive/refs/${GIT_REF}.zip && \
    unzip /source/master.zip -d /source/ && \
    echo "Download complete"

# Debug: Show what we downloaded
RUN if [ "$DEBUG" = "true" ]; then \
        echo "=== SOURCE STRUCTURE ===" && \
        ls -la /source/ && \
        echo "=== EXTRACTED DIRECTORY ===" && \
        cd /source/*/ && ls -la && \
        echo "=== PACKAGE.JSON ===" && \
        cat package.json | head -20; \
    fi

# Install dependencies
RUN echo "=== INSTALLING DEPENDENCIES ===" && \
    cd /source/*/ && \
    yarn install && \
    echo "Dependencies installed"

# Build with gulp
RUN echo "=== RUNNING GULP BUILD ===" && \
    cd /source/*/ && \
    gulp && \
    echo "Gulp build complete"

# Debug: Check what gulp created
RUN if [ "$DEBUG" = "true" ]; then \
        echo "=== POST-GULP STRUCTURE ===" && \
        cd /source/*/ && \
        ls -la && \
        echo "=== SNAPPYMAIL DIRECTORY ===" && \
        if [ -d "snappymail" ]; then \
            ls -la snappymail/ && \
            echo "=== SNAPPYMAIL SUBDIRECTORIES ===" && \
            find snappymail/ -type d -maxdepth 2; \
        else \
            echo "ERROR: snappymail directory not found!" && \
            find . -name "*snap*" -type d; \
        fi; \
    fi

# Extract version and create archive
RUN echo "=== CREATING RELEASE ARCHIVE ===" && \
    cd /source/*/ && \
    VERSION=$(php -r "echo json_decode(file_get_contents('package.json'))->version;") && \
    echo "Building version: $VERSION" && \
    echo $VERSION > /version && \
    \
    if [ -d "snappymail" ]; then \
        echo "Found snappymail directory, creating archive..." && \
        cd snappymail && \
        \
        if [ "$DEBUG" = "true" ]; then \
            echo "=== ARCHIVE CONTENTS ===" && \
            find . -type f | head -20 && \
            echo "... (showing first 20 files)"; \
        fi && \
        \
        zip -r /build-stage-artifact.zip . && \
        echo "Archive created successfully" && \
        ls -la /build-stage-artifact.zip; \
    else \
        echo "ERROR: snappymail directory not found!" && \
        echo "Available directories:" && \
        find . -type d -maxdepth 2 && \
        exit 1; \
    fi

# Verify the archive
RUN echo "=== VERIFYING ARCHIVE ===" && \
    if [ -f "/build-stage-artifact.zip" ]; then \
        ARCHIVE_SIZE=$(stat -c%s /build-stage-artifact.zip) && \
        echo "Archive size: $ARCHIVE_SIZE bytes" && \
        if [ $ARCHIVE_SIZE -gt 1000000 ]; then \
            echo "Archive size looks good (>1MB)" && \
            if [ "$DEBUG" = "true" ]; then \
                echo "=== ARCHIVE CONTENTS PREVIEW ===" && \
                unzip -l /build-stage-artifact.zip | head -20; \
            fi; \
        else \
            echo "WARNING: Archive seems too small ($ARCHIVE_SIZE bytes)" && \
            unzip -l /build-stage-artifact.zip; \
        fi; \
    else \
        echo "ERROR: Archive file not found!" && \
        ls -la / && \
        exit 1; \
    fi && \
    echo "Archive verification complete"

FROM php:7.4-apache

# Copy configuration files
COPY ./snappymail.conf /etc/apache2/sites-available/snappymail.conf
COPY ./mail.example.com.pem /etc/certs/mail.example.com.pem

# Copy build artifacts
COPY --from=builder /version /version
COPY --from=builder /build-stage-artifact.zip /build-stage-artifact.zip

# Install and extract SnappyMail
RUN echo "=== INSTALLING SNAPPYMAIL ===" && \
    export VERSION=$(cat /version) && \
    echo "Installing version: $VERSION" && \
    cp /build-stage-artifact.zip /snappymail-$VERSION.zip && \
    \
    apt-get update && apt-get install -y unzip && \
    \
    echo "Extracting archive..." && \
    unzip -o /snappymail-$VERSION.zip -d /var/www/snappymail && \
    \
    echo "Setting permissions..." && \
    chown www-data:www-data /var/www/snappymail/ -R && \
    \
    echo "=== INSTALLATION VERIFICATION ===" && \
    ls -la /var/www/snappymail/ && \
    \
    if [ -f "/var/www/snappymail/index.php" ]; then \
        echo "✓ index.php found" && \
        head -5 /var/www/snappymail/index.php; \
    else \
        echo "✗ index.php not found" && \
        find /var/www/snappymail/ -name "*.php" | head -10; \
    fi && \
    \
    echo "Installation complete"

# Configure Apache
RUN echo "=== CONFIGURING APACHE ===" && \
    a2ensite snappymail.conf && \
    a2enmod rewrite && \
    a2enmod ssl && \
    echo "Apache configuration complete"

# Cleanup
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -f /build-stage-artifact.zip /snappymail-*.zip

WORKDIR /var/www/snappymail

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# Add labels for better container management
LABEL description="SnappyMail Docker Container"
LABEL version="dynamic"
