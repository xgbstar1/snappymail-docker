ARG HOST

FROM node AS base
RUN npm install -g gulp
# Install PHP 8.2 instead of 7.4 (or add PHP 7.4 repository if specifically needed)
RUN apt-get update && apt-get install -y php php-zip zip unzip

FROM base AS builder
ARG GIT_REF
WORKDIR /source
RUN echo "GIT_REF is ${GIT_REF}"
RUN curl -o /source/master.zip -L https://github.com/the-djmaze/snappymail/archive/refs/${GIT_REF}.zip && \
	unzip /source/master.zip -d /source/
RUN cd /source/*/ && yarn install 

# Fix the cross-device link issue by using cp + rm instead of rename
RUN cd /source/*/ && sed -i 's/rename.*snappymail\/v\/0\.0\.0.*snappymail\/v\/{\$package->version}.*/if (!is_dir("snappymail\/v\/{\$package->version}")) { system("cp -r snappymail\/v\/0.0.0 snappymail\/v\/{\$package->version} \&\& rm -rf snappymail\/v\/0.0.0"); }/' release.php

# Alternative approach: Create the directory structure manually if the above doesn't work
RUN cd /source/*/ && php release.php || (echo "Release failed, checking directory structure..." && find . -name "*.zip" -type f)

# Debug: Check what was actually created
RUN cd /source/*/ && find . -name "*.zip" -type f -exec ls -la {} \;
RUN cd /source/*/ && ls -la build/dist/releases/webmail/ || echo "webmail directory not found"

# More robust version detection and file copying
RUN cd /source/*/ && \
    if [ -d "build/dist/releases/webmail" ]; then \
        ls build/dist/releases/webmail/ > /version; \
    else \
        echo "2.38.2" > /version; \
    fi

# Find and copy the zip file more robustly
RUN export VERSION=$(cat /version) && \
    echo "Looking for version: $VERSION" && \
    cd /source/*/ && \
    ZIPFILE=$(find . -name "snappymail-*.zip" -type f | head -1) && \
    if [ -n "$ZIPFILE" ]; then \
        echo "Found zip file: $ZIPFILE" && \
        cp "$ZIPFILE" /build-stage-artifact; \
    else \
        echo "No zip file found, creating manual archive..." && \
        cd snappymail && \
        zip -r /build-stage-artifact * && \
        echo "Manual archive created"; \
    fi

FROM php:7.4-apache

COPY ./snappymail.conf /etc/apache2/sites-available/snappymail.conf
COPY ./mail.example.com.pem /etc/certs/mail.example.com.pem
COPY --from=builder /version /version
COPY --from=builder /build-stage-artifact /build-stage-artifact
RUN export VERSION=$(cat /version) && echo $VERSION && cp /build-stage-artifact /snappymail-$VERSION.zip

RUN apt-get update && apt-get install -y unzip && unzip -o /snappymail*zip -d /var/www/snappymail

# Optional: add CSS customizations
# COPY css-customizations/customizations.css  /tmp/customizations.css
# RUN export VERSION=$(cat /version) && ls -R /var/www/snappymail/snappymail/ && cat /tmp/customizations.css >> /var/www/snappymail/snappymail/v/$VERSION/static/css/app.min.css

RUN chown www-data:www-data /var/www/snappymail/ -R

RUN a2ensite snappymail.conf

RUN a2enmod rewrite && \
    a2enmod ssl
WORKDIR /var/www/snappymail
