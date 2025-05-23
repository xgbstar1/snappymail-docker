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
RUN cd /source/*/ && sed -i 's_^if.*rename.*snappymail.v.0.0.0.*$_if (!!system("mv snappymail/v/0.0.0 snappymail/v/{$package->version}")) {_' release.php  || true
RUN cd /source/*/ && php release.php
RUN ls /source/*/build/dist/releases/webmail/ > /version
RUN export VERSION=$(cat /version) && echo $VERSION && cp /source/*/build/dist/releases/webmail/$VERSION/snappymail-$VERSION.zip /build-stage-artifact

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
