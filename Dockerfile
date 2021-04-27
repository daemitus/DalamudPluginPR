FROM alpine:3

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

RUN apk add github-cli jq 

ENTRYPOINT ["/entrypoint.sh"]