FROM nginx:1.29-alpine
COPY frontend/index.html /usr/share/nginx/html/index.html
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
RUN chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx /var/run \
    && sed -i 's/listen 8080;/listen 8080;/' /etc/nginx/conf.d/default.conf
USER nginx
EXPOSE 8080

