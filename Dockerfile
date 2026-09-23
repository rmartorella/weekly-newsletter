ARG PROXY=us-docker.pkg.dev/catalant-jenkins/docker-hub-proxy

FROM ${PROXY}/library/python:3.13-alpine@sha256:7415fbc3c9e4979cc717d92377ab2bc7b2b4a2af1ac03cc52b5f3f88efedaf3a AS csp
WORKDIR /build
COPY scripts/gen_csp.py ./scripts/gen_csp.py
COPY src/ ./src/
RUN mkdir -p /out && python3 scripts/gen_csp.py src /out/security-headers.conf

FROM ${PROXY}/nginxinc/nginx-unprivileged:1.30.5-alpine-slim@sha256:c2c3905bda3dc8de80023e19bed0a45745279d26e5586cdee64370c8f9b12348
USER root
RUN rm -f /etc/nginx/conf.d/default.conf \
 && rm -rf /usr/share/nginx/html \
 && mkdir -p /etc/nginx/snippets /usr/share/nginx/html
COPY --chown=root:root nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=csp --chown=root:root /out/security-headers.conf /etc/nginx/snippets/security-headers.conf
COPY --chown=root:root src/ /usr/share/nginx/html/
RUN chmod 644 /etc/nginx/conf.d/default.conf /etc/nginx/snippets/security-headers.conf \
 && find /usr/share/nginx/html -type d -exec chmod 555 {} + \
 && find /usr/share/nginx/html -type f -exec chmod 444 {} + \
 && nginx -t \
 && rm -f /tmp/nginx.pid
USER 101
EXPOSE 8080
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/usr/bin/test", "-r", "/usr/share/nginx/html/index.html"]
CMD ["nginx", "-g", "daemon off;"]
