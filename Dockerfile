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

# Install dependencies
RUN echo "=== INSTALLING DEPENDENCIES ===" && \
    cd /source/*/ && \
    yarn install && \
    echo "Dependencies installed"

# Create a fixed version of release.php
RUN echo "=== CREATING FIXED RELEASE.PHP ===" && \
    cd /source/*/ && \
    cp cli/release.php cli/release.php.backup && \
    cat > cli/release_fixed.php << 'EOF'
#!/usr/bin/php
<?php
define('ROOT_DIR', dirname(__DIR__));
chdir(ROOT_DIR);

$options = getopt('', ['aur','docker','plugins','skip-gulp','debian','nextcloud','owncloud','cpanel','sign']);

if (isset($options['plugins'])) {
	require(ROOT_DIR . '/build/plugins.php');
}

$gulp = trim(`which gulp`);
if (!$gulp) {
	exit('gulp not installed, run as root: npm install --global gulp-cli');
}

$package = json_decode(file_get_contents('package.json'));

$destPath = "build/dist/releases/webmail/{$package->version}/";
is_dir($destPath) || mkdir($destPath, 0777, true);

$zip_destination = "{$destPath}snappymail-{$package->version}.zip";
$tar_destination = "{$destPath}snappymail-{$package->version}.tar";

@unlink($zip_destination);
@unlink($tar_destination);
@unlink("{$tar_destination}.gz");

if (!isset($options['skip-gulp'])) {
	echo "\x1b[33;1m === Gulp === \x1b[0m\n";
	passthru($gulp, $return_var);
	if ($return_var) {
		exit("gulp failed with error code {$return_var}\n");
	}

	$cmddir = escapeshellcmd(ROOT_DIR) . '/snappymail/v/0.0.0/static';

	if ($gzip = trim(`which gzip`)) {
		echo "\x1b[33;1m === Gzip *.js and *.css === \x1b[0m\n";
		passthru("{$gzip} -k --best {$cmddir}/js/*.js");
		passthru("{$gzip} -k --best {$cmddir}/js/min/*.js");
		passthru("{$gzip} -k --best {$cmddir}/css/admin*.css");
		passthru("{$gzip} -k --best {$cmddir}/css/app*.css");
		unlink(ROOT_DIR . '/snappymail/v/0.0.0/static/js/boot.js.gz');
		unlink(ROOT_DIR . '/snappymail/v/0.0.0/static/js/min/boot.min.js.gz');
	}

	if ($brotli = trim(`which brotli`)) {
		echo "\x1b[33;1m === Brotli *.js and *.css === \x1b[0m\n";
		passthru("{$brotli} -k --best {$cmddir}/js/*.js");
		passthru("{$brotli} -k --best {$cmddir}/js/min/*.js");
		passthru("{$brotli} -k --best {$cmddir}/css/admin*.css");
		passthru("{$brotli} -k --best {$cmddir}/css/app*.css");
		unlink(ROOT_DIR . '/snappymail/v/0.0.0/static/js/boot.js.br');
		unlink(ROOT_DIR . '/snappymail/v/0.0.0/static/js/min/boot.min.js.br');
	}
}

// Fixed version directory handling - use copy instead of rename
if (is_dir('snappymail/v/0.0.0') && !is_dir("snappymail/v/{$package->version}")) {
	echo "Creating version directory: snappymail/v/{$package->version}\n";
	exec("cp -r snappymail/v/0.0.0 snappymail/v/{$package->version}");
}

echo "\x1b[33;1m === Zip/Tar === \x1b[0m\n";

$zip = new ZipArchive();
if (!$zip->open($zip_destination, ZIPARCHIVE::CREATE)) {
	exit("Failed to create {$zip_destination}");
}

$tar = new PharData($tar_destination);

$files = new RecursiveIteratorIterator(new RecursiveDirectoryIterator('snappymail/v'), RecursiveIteratorIterator::SELF_FIRST);
foreach ($files as $file) {
	$file = str_replace('\\', '/', $file);
	if (!in_array(substr($file, strrpos($file, '/')+1), array('.', '..'))) {
		if (is_dir($file)) {
			$zip->addEmptyDir($file);
		} else if (is_file($file)) {
			$zip->addFile($file);
		}
	}
}

if ($options['docker']) {
	$tar->buildFromDirectory('./snappymail/', "@v/{$package->version}@");
} else {
	$tar->buildFromDirectory('./', "@snappymail/v/{$package->version}@");
}

$zip->addFile('data/.htaccess');
$tar->addFile('data/.htaccess');

$zip->addFromString('data/VERSION', $package->version);
$tar->addFromString('data/VERSION', $package->version);

$zip->addFile('data/README.md');
$tar->addFile('data/README.md');

if ($options['aur']) {
	$data = '<?php
function __get_custom_data_full_path()
{
	return \'/var/lib/snappymail\';
}
';
	$zip->addFromString('include.php', $data);
	$tar->addFromString('include.php', $data);
} else {
	$zip->addFile('_include.php');
	$tar->addFile('_include.php');
}

$zip->addFile('.htaccess');
$tar->addFile('.htaccess');

$index = file_get_contents('index.php');
$index = str_replace('0.0.0', $package->version, $index);
$zip->addFromString('index.php', $index);
$tar->addFromString('index.php', $index);

$zip->addFile('README.md');
$tar->addFile('README.md');

$zip->close();

$tar->compress(Phar::GZ);
unlink($tar_destination);
$tar_destination .= '.gz';

echo "{$zip_destination} created\n{$tar_destination} created\n";

// Clean up - restore original structure
if (is_dir("snappymail/v/{$package->version}") && !is_dir('snappymail/v/0.0.0')) {
	echo "Restoring original directory structure\n";
	exec("cp -r snappymail/v/{$package->version} snappymail/v/0.0.0");
}

file_put_contents("{$destPath}core.json", '{
	"version": "'.$package->version.'",
	"file": "../latest.tar.gz",
	"warnings": []
}');

echo "Release build completed successfully!\n";
EOF
    chmod +x cli/release_fixed.php && \
    echo "Fixed release.php created"

# Debug: Show the differences if debug is enabled
RUN if [ "$DEBUG" = "true" ]; then \
        echo "=== USING FIXED RELEASE SCRIPT ===" && \
        cd /source/*/ && \
        echo "Original problematic lines:" && \
        grep -n "rename" cli/release.php.backup || true; \
    fi

# Run the fixed release build
RUN echo "=== BUILDING RELEASE ===" && \
    cd /source/*/ && \
    php cli/release_fixed.php && \
    echo "Release build complete"

# Debug: Check what was built
RUN if [ "$DEBUG" = "true" ]; then \
        echo "=== BUILD RESULTS ===" && \
        cd /source/*/ && \
        find build/dist/releases/webmail/ -name "*.zip" -o -name "*.tar.gz" | head -10 && \
        ls -la build/dist/releases/webmail/*/; \
    fi

# Extract version and copy artifact
RUN echo "=== EXTRACTING RELEASE ARTIFACT ===" && \
    cd /source/*/ && \
    VERSION=$(ls build/dist/releases/webmail/ | head -1) && \
    echo "$VERSION" > /version && \
    echo "Found version: $VERSION" && \
    \
    # Copy the zip file (preferred) or tar.gz
    if [ -f "build/dist/releases/webmail/$VERSION/snappymail-$VERSION.zip" ]; then \
        cp "build/dist/releases/webmail/$VERSION/snappymail-$VERSION.zip" /build-stage-artifact && \
        echo "Copied zip artifact"; \
    elif [ -f "build/dist/releases/webmail/$VERSION/snappymail-$VERSION.tar.gz" ]; then \
        cp "build/dist/releases/webmail/$VERSION/snappymail-$VERSION.tar.gz" /build-stage-artifact && \
        echo "Copied tar.gz artifact"; \
    else \
        echo "ERROR: No release archive found" && \
        ls -la "build/dist/releases/webmail/$VERSION/" && \
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
        curl \
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
