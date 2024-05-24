# CI/CD Tamiyochi Laravel Project - Penugasan 3

Nama : Alief Gilang Permana Putra

NRP : 5025221193

## Pengerjaan
  - [Persiapan Server](#persiapan-server)
  - [Kontainerisasi dengan Docker](#kontainerisasi-dengan-docker)
  - [CI/CD dengan Github Actions]()

## Persiapan Server
Kita akan menggunakan virtual machine Azure dengan OS Debian. Contoh server yang telah berjalan yang dapat diakses di [sini](http://104.214.190.91).

Terdapat beberapa langkah yang perlu dilakukan
1. Login ssh dengan command ```ssh -i "ssh-key.pem" USER@IP_HOST```
2. Install dan setting docker dengan command berikut:
   ```bash
   # Add Docker's official GPG key:
   sudo apt-get update
   sudo apt-get install ca-certificates curl
   sudo install -m 0755 -d /etc/apt/keyrings
   sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
   sudo chmod a+r /etc/apt/keyrings/docker.asc
   
   # Add the repository to Apt sources:
   echo \
   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
   $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
   sudo apt-get update

   # Install docker
   sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
   
   # verify installation
   sudo docker run hello-world

   # Add current user to docker group
   sudo usermod -aG docker $USER
   newgrp docker
   ```
3. Clone git repository ke server dengan ```git clone https://github.com/lyfesan/tamiyochi-laravel.git```
   
Server siap untuk digunakan 

## Kontainerisasi dengan Docker
Pada deployment ini, kita akan membuat 3 kontainer dengan konfigurasi sebagai berikut :
1. Aplikasi Tamiyochi
2. Database MySQL
3. Webserver Nginx

### Dockerfile untuk Tamiyochi
Untuk aplikasi tamiyochi, kita akan membuat image custom sendiri yang akan di push ke dockerhub setiap kali terdapat push pada branch main pada repository ini. Berikut adalah Dockerfile untuk custom image menggunakan base image php:8.1-fpm:

```Dockerfile
FROM php:8.1-fpm

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
```

Pada saat kontainer dijalankan menggunakkkan image ini, maka ```setup-tamiyochi.sh``` akan dipanggil untuk setup aplikasi tamiyochi dan menjalankan php-fpm yang akan ditampilkan menggunakan webserver nginx pada kontainer terpisah, berikut adalah isi ```setup-tamiyochi.sh```

```bash
#!/bin/bash

php artisan key:generate
php artisan migrate
php artisan db:seed
php artisan storage:link
php-fpm
```

### Manajemen Kontainer dengan Docker Compose

Untuk mengatur seluruh kontainer, kita akan menggunakan docker compose. Berikut adalah isi konfigurasi ```docker-compose.yaml```:

```yaml
services:

  mysql:
    image: mysql
    container_name: mysql
    volumes:
      - tamiyochi-db:/var/lib/mysql
    restart: always
    ports: 
      - "3306:3306"
    tty: true
    environment:
      MYSQL_DATABASE: pbkk
      MYSQL_ROOT_PASSWORD: tamiyochi 
    healthcheck:
      test: ["CMD", 'mysqladmin', 'ping', '-h', 'localhost', '-u', 'root', '-p tamiyochi' ]
      timeout: 10s
      retries: 5

  tamiyochi-laravel:
    image: lyfesan/tamiyochi-laravel
    restart: always
    container_name: app
    ports:
      - "9000:9000"
    volumes:
      - tamiyochi-php:/var/www/html
    depends_on:
      mysql:
        condition: service_healthy
  
  webserver:
    image: nginx
    container_name: nginx-webserver
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./tamiyochi-nginx.conf:/etc/nginx/conf.d/default.conf
      - tamiyochi-php:/var/www/html
    depends_on:
      - mysql
      - tamiyochi-laravel

volumes:
  tamiyochi-db:
    driver: local
  tamiyochi-php:
    driver: local
```

Konfigurasi ini akan menggunakan 2 docker volume, ```tamiyochi-db``` digunakan untuk menyimpan database mysql dan ```tamiyochi-php``` digunakan untuk menyimpan aplikasi tamiyochi yang terdapat pada kontainer ```app``` pada service ```tamiyochi-laravel``` sehingga dapat digunakan pada ```webserver``` untuk ditampilkan pada port 80. ```tamiyochi-laravel``` dan ```webserver``` tidak akan berjalan hingga ```mysql``` berjalan dan dilakukan ```healthcheck```. Hal ini dilakukan agar ```tamiyochi-laravel``` tidak error saat mengakses database ketika melakukan konfigurasi dengan ```php artisan```. 

### Konfigurasi Nginx
Kita akan melakukan bind konfigurasi nginx untuk aplikasi tamiyochi agar interface fastcgi php-fpm dapat ditampilkan pada port 80 yang akan disimpan pada ```/etc/nginx/conf.d/default.conf``` menggunakan file ```tamiyochi-nginx.conf```. Berikut adalah isinya:

```conf
server {
    listen 80;
    server_name localhost;
    root /var/www/html/tamiyochi-laravel/public/;
    index index.php index.html index.htm;

    location / {
        try_files $uri /index.php$is_args$args;
    }

    location ~ ^/.+\.php(/|$) {
        fastcgi_pass app:9000;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param SCRIPT_NAME $fastcgi_script_name;
    }
}
```

## CI/CD dengan Github Actions
Agar setiap perubahan pada repository git dapat langsung diterapkan, kita akan menggunakan github action dengan nama ```tamiyochi-deploy.yml```. Berikut adalah isi konfigurasinya:

```yml
name: ci/cd server 

on: 
  push:
    branches: 
    - 'main'

jobs:
  docker_build_push:
      runs-on: ubuntu-latest
      steps:
        - name: Set up Docker Buildx
          uses: docker/setup-buildx-action@v3

        - name: Login to Docker Hub
          uses: docker/login-action@v3
          with:
            username: ${{ secrets.DOCKERHUB_USERNAME }}
            password: ${{ secrets.DOCKERHUB_TOKEN }}
            
        - name: Build and push
          uses: docker/build-push-action@v5
          with:   
            push: true
            tags: ${{ secrets.DOCKERHUB_USERNAME }}/tamiyochi-laravel:latest
            cache-from: type=gha
            cache-to: type=gha,mode=max

  server_deploy:
    needs: docker_build_push
    runs-on: ubuntu-latest

    steps:
      - name: Pull github code and redeploy docker containers
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ vars.SERVER_IP }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_KEY }}
          port: 22
          script: |
            cd tamiyochi-laravel
            git pull --no-edit
            docker compose down
            docker pull lyfesan/tamiyochi-laravel
            docker compose up -d
```

#### Penjelasan:

Terdapat 2 jobs yang akan dilakukan ketika terdapat commit baru, yaitu ```docker_build_push``` dan ```server_deploy```. 
1. docker_build_push
   
   Job ini digunakan untuk build tamiyochi image menggunakan ```Dockerfile``` yang terdapat pada repository dan push image baru ke dockerhub

2. server_deploy
   
   Job ini digunakan untuk login ssh ke server untuk melakukan git pull repository tamiyochi-laravel dan redeploy kontainer docker menggunakan file ```docker-compose.yml``` yang ada dalam repository

Kendala :
1. ```php artisan migrate``` tidak dapat connect dengan ```mysql``` karena connection refused padahal username dan password sudah benar. Merujuk artikel [ini](https://stackoverflow.com/questions/40561433/docker-mysql-2002-connection-refused) pada ```.env``` di dalam aplikasi tamiyochi, ```DB_HOST``` harus diset dengan nama ```mysql```, yaitu nama service mysql pada file docker compose sehingga artisan dapat mengakses database. Selain itu, penambahan ```healthcheck``` pada service ```mysql``` digunakan agar kontainer ```tamiyochi-laravel``` tidak berjalan terlebih dahulu sebelum kontainer ```mysql``` berjalan dengan sempurna
