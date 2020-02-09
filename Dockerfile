FROM cyclos/cyclos:4.11.2

RUN set -x; \
        apt-get update \
        && apt-get install -y --no-install-recommends python3 \
        python3-requests python3-slugify python3-yaml
