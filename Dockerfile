ARG HOST

FROM node AS builder
WORKDIR /source/snappymail-master
RUN npm install -g gulp
RUN apt-get update && apt-get install -y php7.4 && apt-get install -y php7.4-zip
# Optional: clone the repo...
#RUN git clone https://github.com/the-djmaze/snappymail.git /source
RUN apt-get install -y zip unzip
RUN curl -o /source/master.zip -L https://github.com/the-djmaze/snappymail/archive/refs/heads/master.zip && \
	unzip /source/master.zip -d /source/
RUN yarn install 
RUN sed -i 's_^if.*rename.*snappymail.v.0.0.0.*$_if (!!system("mv snappymail/v/0.0.0 snappymail/v/{$package->version}")) {_' release.php 
RUN php release.php
RUN ls /source/snappymail-master/build/dist/releases/webmail/ > /version
RUN export VERSION=$(cat /version) && echo $VERSION && cp /source/snappymail-master/build/dist/releases/webmail/$VERSION/snappymail-$VERSION.zip /build-stage-artifact

FROM php:7.4-apache


RUN apt-get update && \
apt-get install -y unzip wget

COPY ./snappymail.conf /etc/apache2/sites-available/snappymail.conf
COPY ./mail.example.com.pem /etc/certs/mail.example.com.pem
COPY --from=builder /version /version
COPY --from=builder /build-stage-artifact /build-stage-artifact
RUN export VERSION=$(cat /version) && echo $VERSION && cp /build-stage-artifact /snappymail-$VERSION.zip

RUN unzip -o /snappymail*zip -d /var/www/snappymail

# Optional: add CSS customizations
# COPY css-customizations/customizations.css  /tmp/customizations.css
# RUN export VERSION=$(cat /version) && ls -R /var/www/snappymail/snappymail/ && cat /tmp/customizations.css >> /var/www/snappymail/snappymail/v/$VERSION/static/css/app.min.css

RUN chown www-data:www-data /var/www/snappymail/ -R


RUN a2ensite snappymail.conf

RUN a2enmod rewrite && \
    a2enmod ssl
