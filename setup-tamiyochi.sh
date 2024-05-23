#!/bin/bash

php artisan key:generate
php artisan db:seed
php artisan storage:link
yarn build
php-fpm