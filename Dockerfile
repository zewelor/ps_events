FROM ghcr.io/zewelor/ruby:3.4.4-slim AS base

ARG BUNDLER_VERSION=2.6.8
ARG RUNTIME_PACKAGES=""
ARG DEV_PACKAGES="build-essential git libyaml-dev"

# We mount whole . dir into app, so vendor/bundle would get overwritten
ENV BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    GEM_HOME=/bundle

ENV PATH="${BUNDLE_BIN}:${PATH}"

# install dev dependencies
# hadolint ignore=SC2086,DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    $RUNTIME_PACKAGES && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    gem install bundler -v "$BUNDLER_VERSION"

FROM base AS basedev

# install dev dependencies
# hadolint ignore=SC2086,DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    $DEV_PACKAGES && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

FROM basedev AS dev

RUN mkdir -p "$BUNDLE_PATH" && \
    chown -R app:app "$BUNDLE_PATH"

USER app

# https://code.visualstudio.com/remote/advancedcontainers/avoid-extension-reinstalls
RUN mkdir -p "$HOME/.vscode-server/"

FROM basedev AS baseliveci

# Workdir set in base image
# hadolint ignore=DL3045
COPY --chown=app:app Gemfile Gemfile.lock ./

FROM baseliveci AS ci

# hadolint ignore=SC2086
RUN mkdir -p $BUNDLE_PATH && \
    chown -R app $BUNDLE_PATH

RUN bundle install "-j$(nproc)" --retry 3 && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

FROM baseliveci AS live_builder

ENV BUNDLE_WITHOUT="development:test"

RUN bundle install "-j$(nproc)" --retry 3 && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

FROM base AS live

# We enable `BUNDLE_DEPLOYMENT` so that bundler won't take the liberty to upgrade any gems.
ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_WITHOUT="development:test" \
    RUBYOPT='--disable-did_you_mean'

# Workdir set in base image
# hadolint ignore=DL3045
COPY --chown=app:app --from=live_builder $BUNDLE_PATH $BUNDLE_PATH
# hadolint ignore=DL3045
COPY --chown=app:app . ./

USER app

ENTRYPOINT ["/usr/bin/catatonit", "--", "bin/cli"]
