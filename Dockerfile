# Global arguments
ARG APP_UID=1000
ARG APP_GID=1000

FROM ghcr.io/eudaldgr/scratchless AS scratchless

# Build stage
FROM docker.io/alpine AS build
ARG APP_VERSION \
  APP_ROOT \
  APP_UID \
  APP_GID \
  TARGETARCH \
  TARGETVARIANT

RUN set -ex; \
  apk --no-cache --update add \
  autoconf \
  automake \
  binutils \
  gcc \
  libbsd-dev \
  libtool \
  m4 \
  make \
  musl-dev \
  nspr \
  nss \
  nss-dev \
  sqlite-libs \
  zlib;

RUN set -ex; \
  apk --no-cache --update add \
  --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
  corosync-dev;

RUN set -ex; \
  wget -qO- "https://github.com/corosync/corosync-qdevice/archive/v${APP_VERSION}.tar.gz" | tar xz;

RUN set -ex; \
  cd corosync-qdevice-${APP_VERSION}; \
  ./autogen.sh;

RUN set -ex; \
  cd corosync-qdevice-${APP_VERSION}; \
  ./configure \
  --sbindir=/usr/bin \
  --sysconfdir=/etc \
  --libdir=/lib \
  --disable-systemd \
  --disable-qdevices \
  --enable-qnetd \
  --localstatedir=/var;

RUN set -ex; \
  cd corosync-qdevice-${APP_VERSION}; \
  sed -i '1i#include <stddef.h>' qdevices/log-common.c;

RUN set -ex; \
  cd corosync-qdevice-${APP_VERSION}; \
  make;

RUN set -ex; \
  cd corosync-qdevice-${APP_VERSION}; \
  make install;

RUN set -ex; \
  cd corosync-qdevice-${APP_VERSION}; \
  strip /usr/bin/corosync-qnetd;

COPY --from=scratchless / ${APP_ROOT}/

# Collect all runtime dependencies
RUN set -ex; \
  mkdir -p \
  ${APP_ROOT}/lib \
  ${APP_ROOT}/bin \
  ${APP_ROOT}/etc;

RUN set -ex; \
  mkdir -p \
  ${APP_ROOT}/etc/corosync/qnetd/nssdb \
  ${APP_ROOT}/var/lock \
  ${APP_ROOT}/var/run/corosync-qnetd; \
  chmod 0770 ${APP_ROOT}/var/run/corosync-qnetd ${APP_ROOT}/var/lock; \
  chown -R ${APP_UID}:${APP_GID} ${APP_ROOT}/var/run/corosync-qnetd ${APP_ROOT}/var/lock;

RUN set -ex; \
  cd corosync-qdevice-${APP_VERSION}; \
  cp /usr/bin/corosync-qnetd ${APP_ROOT}/bin/;

# Copy all required shared libraries
RUN set -ex; \
  ldd ${APP_ROOT}/bin/corosync-qnetd | awk '{if (match($3,"/")) print $3}' | xargs -I '{}' cp -v '{}' ${APP_ROOT}/lib/ || true;

# NSS/NSPR/SQLite/ZLib carregades dinàmicament
RUN set -ex; \
  cp -v /usr/lib/libfreebl3.so          ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libfreeblpriv3.so      ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libnss*.so             ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libnssckbi-testlib.so  ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libnssckbi.so          ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libnsssysinit.so       ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libnssutil3.so         ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libsmime*.so           ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libsoftokn3.so         ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libssl*.so             ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libnspr*.so     ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libplc*.so      ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libplds*.so     ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libsqlite3.so.0 ${APP_ROOT}/lib/ || true; \
  cp -v /usr/lib/libz.so.1       ${APP_ROOT}/lib/ || true;

# Copy the dynamic linker
RUN set -ex; \
  cp /lib/ld-musl-*.so.1 ${APP_ROOT}/lib/;

# Final scratch image
FROM scratch

ARG TARGETPLATFORM \
  TARGETOS \
  TARGETARCH \
  TARGETVARIANT \
  APP_IMAGE \
  APP_NAME \
  APP_VERSION \
  APP_ROOT \
  APP_UID \
  APP_GID \
  APP_NO_CACHE

ENV APP_IMAGE=${APP_IMAGE} \
  APP_NAME=${APP_NAME} \
  APP_VERSION=${APP_VERSION} \
  APP_ROOT=${APP_ROOT}

COPY --from=build ${APP_ROOT}/ /

ENV HOME=/etc/corosync/qnetd
VOLUME /etc/corosync/qnetd

EXPOSE 5403

USER ${APP_UID}:${APP_GID}
ENTRYPOINT ["/bin/corosync-qnetd", "-f"]