FROM alpine:3.20.0

RUN apk add --no-cache \
  bash curl

RUN set -eux ; \
  mkdir /ghjk ; cd /ghjk ; \
  [ "$(uname -m)" = "aarch64" ] && arch="arm64" || arch="amd64" ; \
  curl -LO "https://dl.k8s.io/release/v1.29.5/bin/linux/${arch}/kubectl" ; \
  chmod +x kubectl ; \
  mv kubectl /usr/local/bin ; \
  rm -rf /ghjk

WORKDIR /app
COPY app .

ENTRYPOINT [ "/app/entrypoint.sh" ]
