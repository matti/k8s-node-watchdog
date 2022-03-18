FROM --platform=linux/amd64 alpine:3.15.0

RUN apk add --no-cache \
  bash curl

RUN mkdir /ghjk && cd /ghjk \
  && curl -Lfso kubectl https://storage.googleapis.com/kubernetes-release/release/v1.21.9/bin/linux/amd64/kubectl  \
  && chmod +x kubectl  \
  && mv kubectl /usr/bin  \
  && rm -rf /ghjk

WORKDIR /app
COPY app .

ENTRYPOINT [ "/app/entrypoint.sh" ]