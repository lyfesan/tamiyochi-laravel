FROM php:8.2-fpm

RUN apt-get update && apt-get install -y \
    build-essential \
    locales \
    zip \
    libzip-dev \
    unzip \
    git \
    curl \
    npm 

# Install composer from web because dependency issue when installing from debian repository
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Install yarn using npm and pdo_mysql using available script from php image
RUN npm install -g yarn && docker-php-ext-install pdo pdo_mysql

COPY tamiyochi-app/ /var/www/html/tamiyochi-laravel

COPY setup-tamiyochi.sh /usr/local/bin

RUN chmod -R 755 /var/www/html/ && chown -R www-data:www-data /var/www/html/tamiyochi-laravel

WORKDIR /var/www/html/tamiyochi-laravel

RUN composer install && yarn && yarn build

EXPOSE 9000

CMD ["setup-tamiyochi.sh"]