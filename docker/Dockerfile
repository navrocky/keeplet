# Build environment for Keeplet. Used by scripts/build.sh locally and in CI.
# buildpack-deps:*-curl ships ca-certificates, so apt can use HTTPS mirrors
# (plain-HTTP deb.debian.org is blocked on some networks).
FROM buildpack-deps:trixie-curl

RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/debian.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        qt6-declarative-dev-tools \
        qml6-module-qtquick \
        qml6-module-qttest \
        zip \
 && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/lib/qt6/bin:${PATH}" \
    QT_QPA_PLATFORM=offscreen \
    QT_FORCE_STDERR_LOGGING=1 \
    HOME=/tmp \
    LANG=C.UTF-8

WORKDIR /src
