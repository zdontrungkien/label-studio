# syntax=docker/dockerfile:1.3
ARG BUILDPLATFORM=linux/amd64
FROM --platform=${BUILDPLATFORM} node:18 AS frontend-builder

ENV NPM_CACHE_LOCATION=$HOME/.cache/yarn/v6 \
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    NX_REJECT_UNKNOWN_LOCAL_CACHE=0

WORKDIR /label-studio/web

COPY --chown=1001:0 web .
COPY --chown=1001:0 pyproject.toml /label-studio

RUN yarn config set registry https://registry.npmjs.org/
RUN yarn config set network-timeout 1200000 # HTTP timeout used when downloading packages, set to 20 minutes

RUN yarn install --frozen-lockfile && yarn run build


FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LS_DIR=/label-studio \
    PIP_CACHE_DIR=$HOME/.cache \
    POETRY_CACHE_DIR=$HOME/.poetry-cache \
    DJANGO_SETTINGS_MODULE=core.settings.label_studio \
    LABEL_STUDIO_BASE_DATA_DIR=/label-studio/data \
    OPT_DIR=/opt/heartex/instance-data/etc \
    SETUPTOOLS_USE_DISTUTILS=stdlib

WORKDIR $LS_DIR

RUN set -eux \
 && apt-get update \
 && apt-get install --no-install-recommends --no-install-suggests -y \
    build-essential postgresql-client libmysqlclient-dev mysql-client python3-pip python3-dev \
    git libxml2-dev libxslt-dev zlib1g-dev gnupg curl lsb-release libpq-dev dnsutils vim && \
    apt-get purge --assume-yes --auto-remove --option APT::AutoRemove::RecommendsImportant=false \
     --option APT::AutoRemove::SuggestsImportant=false && rm -rf /var/lib/apt/lists/* /tmp/*

RUN pip3 install --upgrade pip setuptools && pip3 install poetry uwsgi uwsgitop


RUN set -eux; \
    curl -sSL https://nginx.org/keys/nginx_signing.key | apt-key add - && \
    echo "deb https://nginx.org/packages/mainline/ubuntu/ $(lsb_release -cs) nginx" >> /etc/apt/sources.list && \
    apt-get update && apt-get install -y nginx && \
    apt-get purge --assume-yes --auto-remove --option APT::AutoRemove::RecommendsImportant=false \
     --option APT::AutoRemove::SuggestsImportant=false && rm -rf /var/lib/apt/lists/* /tmp/* && \
    nginx -v

COPY --chown=1001:0 deploy/default.conf /etc/nginx/nginx.conf

RUN set -eux; \
    mkdir -p $OPT_DIR /var/log/nginx /var/cache/nginx /etc/nginx && \
    chown -R 1001:0 $OPT_DIR /var/log/nginx /var/cache/nginx /etc/nginx

COPY --chown=1001:0 pyproject.toml .
COPY --chown=1001:0 poetry.lock .
COPY --chown=1001:0 README.md .
COPY --chown=1001:0 label_studio/__init__.py ./label_studio/__init__.py

RUN poetry check --lock && POETRY_VIRTUALENVS_CREATE=false poetry install


COPY --chown=1001:0 . .

RUN rm -rf ./label_studio/web
COPY --chown=1001:0 --from=frontend-builder /label-studio/web/dist ./label_studio/web/dist

RUN python3 label_studio/manage.py collectstatic --no-input && \
    chown -R 1001:0 $LS_DIR && \
    chmod -R g=u $LS_DIR

ENV HOME=/label-studio

EXPOSE 8080

USER 1001

ENTRYPOINT ["./deploy/docker-entrypoint.sh"]
CMD ["label-studio"]
