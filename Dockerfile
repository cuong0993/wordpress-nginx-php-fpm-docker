FROM alpine:3.24 as core-plugins

WORKDIR /plugins

RUN apk add -U unzip && apk add -U curl && rm -rf /var/cache/apk/*

# https://wordpress.org/plugins/akismet/
RUN mkdir -p tmp && curl https://downloads.wordpress.org/plugin/akismet.5.7.2.zip >> /tmp/akismet.zip
RUN ls /tmp/
RUN unzip /tmp/akismet.zip -d /tmp/akismet
RUN mv /tmp/akismet/* /plugins

# https://wordpress.org/plugins/wp-stateless/
RUN mkdir -p tmp && curl https://downloads.wordpress.org/plugin/wp-stateless.4.4.3.zip >> /tmp/wp-stateless.zip
RUN ls /tmp/
RUN unzip /tmp/wp-stateless.zip -d /tmp/wp-stateless
RUN mv /tmp/wp-stateless/* /plugins

FROM alpine:3.24 as core-themes

WORKDIR /themes

RUN apk add -U curl && apk add -U curl && rm -rf /var/cache/apk/*

# https://wordpress.org/themes/blogsen/
RUN mkdir -p tmp && curl https://downloads.wordpress.org/theme/blogsen.1.0.0.zip >> /tmp/blogsen.zip
RUN ls /tmp/
RUN unzip /tmp/blogsen.zip -d /tmp/blogsen
RUN mv /tmp/blogsen/* /themes

# https://wordpress.org/themes/blogbell/
RUN mkdir -p tmp && curl https://downloads.wordpress.org/theme/blogbell.3.4.zip >> /tmp/blogbell.zip
RUN ls /tmp/
RUN unzip /tmp/blogbell.zip -d /tmp/blogbell
RUN mv /tmp/blogbell/* /themes

# https://www.alpinelinux.org/downloads/
FROM alpine:3.24

# Build arguments for OCI annotations
ARG BUILD_DATE
ARG VERSION
ARG VCS_REF

# OCI annotations
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.authors="Tim de Pater <code@trafex.nl>"
LABEL org.opencontainers.image.url="https://github.com/TrafeX/docker-wordpress"
LABEL org.opencontainers.image.documentation="https://github.com/TrafeX/docker-wordpress"
LABEL org.opencontainers.image.source="https://github.com/TrafeX/docker-wordpress"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.revision="${VCS_REF}"
LABEL org.opencontainers.image.vendor="TrafeX"
LABEL org.opencontainers.image.title="WordPress with Nginx 1.30 & PHP-FPM 8.5"
LABEL org.opencontainers.image.description="Lightweight WordPress container with Nginx 1.30 & PHP-FPM 8.5 based on Alpine Linux."

# Install packages
RUN apk --no-cache add \
  'php85>=8.5.12' \
  'php85-fpm>=8.5.12' \
  php85-mysqli \
  php85-json \
  php85-openssl \
  php85-curl \
  php85-zlib \
  php85-xml \
  php85-phar \
  php85-intl \
  php85-dom \
  php85-xmlreader \
  php85-xmlwriter \
  php85-exif \
  php85-fileinfo \
  php85-sodium \
  php85-gd \
  php85-simplexml \
  php85-ctype \
  php85-mbstring \
  php85-zip \
  php85-iconv \
  php85-pecl-imagick \
  php85-session \
  php85-tokenizer \
  nginx \
  supervisor \
  curl \
  bash \
  less

# Configure nginx
COPY config/nginx.conf /etc/nginx/nginx.conf

# Configure PHP-FPM
COPY config/fpm-pool.conf /etc/php85/php-fpm.d/zzz_custom.conf
COPY config/php.ini /etc/php85/conf.d/zzz_custom.ini

# Configure supervisord
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# wp-content volume
VOLUME /var/www/wp-content
WORKDIR /var/www/wp-content
RUN chown -R nobody:nobody /var/www

# WordPress
ENV WORDPRESS_VERSION=7.1.3
ENV WORDPRESS_SHA1=491a78c7676b15dffcc69130c6054b8f49228a91

RUN mkdir -p /usr/src

# Upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
# https://wordpress.org/download/releases/
RUN curl -o wordpress.tar.gz -SL https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz \
  && echo "$WORDPRESS_SHA1 *wordpress.tar.gz" | sha1sum -c - \
  && tar -xzf wordpress.tar.gz -C /usr/src/ \
  && rm wordpress.tar.gz \
  && chown -R nobody:nobody /usr/src/wordpress

# Add WP CLI
ENV WP_CLI_CONFIG_PATH=/usr/src/wordpress/wp-cli.yml
RUN curl -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
  && chmod +x /usr/local/bin/wp
COPY --chown=nobody:nobody wp-cli.yml /usr/src/wordpress/

# WP config
COPY --chown=nobody:nobody wp-config.php /usr/src/wordpress
RUN chmod 640 /usr/src/wordpress/wp-config.php

# Link wp-secrets to location on wp-content
RUN ln -s /var/www/wp-content/wp-secrets.php /usr/src/wordpress/wp-secrets.php

RUN \
 rm -f /usr/src/wordpress/wp-content/plugins/hello.php && \
 rm -r /usr/src/wordpress/wp-content/plugins/akismet && \
 rm -r /usr/src/wordpress/wp-content/themes/twentytwentythree && \
 rm -r /usr/src/wordpress/wp-content/themes/twentytwentyfour && \
 rm -r /usr/src/wordpress/wp-content/themes/twentytwentyfive

COPY --from=core-plugins /plugins /usr/src/wordpress/wp-content/plugins
COPY --from=core-themes /themes /usr/src/wordpress/wp-content/themes

# Entrypoint to copy wp-content
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

HEALTHCHECK --timeout=10s CMD curl --silent --fail http://127.0.0.1/wp-login.php
