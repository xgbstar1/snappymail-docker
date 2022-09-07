# snappymail-docker
> Docker image, built twice daily for snappymail

### Why?
The motivation for this repo is to demonstrate and have a basic automated build available for snappymail. As a bonus, the resultant artifact is packaged as a docker container image and published to Dockerhub for convenience.  
  
One practical reason why it's helpful to have this around is that, at this time, snappymail is released every so often, but awesome commits land more frequently, and this repo helps bridge that gap by providing an uptodate build at a frequency of twice a day.  Additional information on folks asking for this or similar solutions is availble here [https://github.com/the-djmaze/snappymail/issues/44#issuecomment-1237062030](the-djmaze/snappymail/issues/44).

### How to use it?

#### Quick
```
docker run -it \
	-d \
  -p 80:80 \
	--restart unless-stopped \
	-p 443:443 \
	-v $(pwd)/volumes/var-www-snappymail-data:/var/www/snappymail/data \
	-v $(pwd)/volumes/etc-apache2-sites-available:/etc/apache2/sites-available \
	-v $(pwd)/volumes/var-log-apache2:/var/log/apache2/ \
  -v $(pwd)/volumes/usr-local-etc-php-conf.d/increase-upload-size.ini:/usr/local/etc/php/conf.d/increase-upload-size.ini \
	-v /etc/letsencrypt/:/etc/letsencrypt/:ro \
	--name snappymail \
	xgbstar1/snappymail-docker:main
```

#### Longer
Here's a sample bash script to get this up and running.
For details on the peripheral files, such as the php config and Apache configuration, see the comment at the following URI since it explains these and provides sample config even though it a locally-built Docker image since it predates this repo's creation.
https://github.com/the-djmaze/snappymail/issues/444 

```
#!/bin/bash

pushd /opt/snappymail

docker rm -f snappymail

#id=$(docker create snappymail)
id=$(docker create xgbstar1/snappymail-docker:main)
docker cp $id:/var/www/snappymail/data/. $(pwd)/volumes/var-www-snappymail-data

docker rm -v $id

find $(pwd)/volumes/var-www-snappymail-data -type d -exec chmod 775 {} \;
find $(pwd)/volumes/var-www-snappymail-data -type f -exec chmod 664 {} \;
#chown -R www-data:wwww-data $(pwd)/volumes/var-www-rainloop-data
chown -R 33:33 $(pwd)/volumes/var-www-snappymail-data

docker run -it \
	-d \
  -p 80:80 \
	--restart unless-stopped \
	-p 443:443 \
	-v $(pwd)/volumes/var-www-snappymail-data:/var/www/snappymail/data \
	-v $(pwd)/volumes/etc-apache2-sites-available:/etc/apache2/sites-available \
	-v $(pwd)/volumes/var-log-apache2:/var/log/apache2/ \
  -v $(pwd)/volumes/usr-local-etc-php-conf.d/increase-upload-size.ini:/usr/local/etc/php/conf.d/increase-upload-size.ini \
	-v /etc/letsencrypt/:/etc/letsencrypt/:ro \
	--name snappymail \
	xgbstar1/snappymail-docker:main


VERSION=$(docker exec snappymail ls /var/www/snappymail/snappymail/v/)
echo "before last"
docker cp snappymail:/var/www/snappymail/snappymail/v/$VERSION/static/css/app.min.css ./
cat css-customizations/customizations.css >> app.min.css
docker cp app.min.css snappymail:/var/www/snappymail/snappymail/v/$VERSION/static/css/.
rm app.min.css

popd
```


