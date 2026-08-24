ARG NGINX_BASE=nginx:1.29-alpine
FROM ${NGINX_BASE}
COPY frontend/index.html /usr/share/nginx/html/index.html
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
RUN chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx /var/run \
    && sed -i 's/listen 8080;/listen 8080;/' /etc/nginx/conf.d/default.conf
# Use the image's nginx UID/GID explicitly for Kubernetes runAsNonRoot checks.
USER 101:101
EXPOSE 8080
