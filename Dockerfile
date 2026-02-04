FROM ghcr.io/zewelor/ruby:4.0.1-slim AS base

ARG RUNTIME_PACKAGES="imagemagick"
ARG DEV_PACKAGES="build-essential git libyaml-dev openssh-client curl jq file xz-utils"
ARG WATCHEXEC_VERSION="2.3.3"

# We mount whole . dir into app, so vendor/bundle would get overwritten
ENV BUNDLE_PATH=/bundle \
  GEM_HOME=/bundle

# install dev dependencies
# hadolint ignore=SC2086,DL3008
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  $RUNTIME_PACKAGES && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

FROM base AS basedev

ENV BUNDLE_AUTO_INSTALL=true

# install dev dependencies
# hadolint ignore=SC2086,DL3008
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  $DEV_PACKAGES && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install watchexec for development containers (replaces rerun)
# hadolint ignore=DL3003
RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    amd64) watchexec_arch="x86_64-unknown-linux-gnu" ;; \
    arm64) watchexec_arch="aarch64-unknown-linux-gnu" ;; \
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
  esac; \
  tmpdir="$(mktemp -d)"; \
  curl -fsSL -o "$tmpdir/watchexec.tar.xz" "https://github.com/watchexec/watchexec/releases/download/v${WATCHEXEC_VERSION}/watchexec-${WATCHEXEC_VERSION}-${watchexec_arch}.tar.xz"; \
  tar -C "$tmpdir" -xJf "$tmpdir/watchexec.tar.xz"; \
  install -m 0755 "$(find "$tmpdir" -type f -name watchexec -print -quit)" /usr/local/bin/watchexec; \
  rm -rf "$tmpdir"

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

ENV BUNDLE_WITHOUT="development:test:jekyll_plugins"

RUN bundle install "-j$(nproc)" --retry 3 && \
  rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

FROM base AS live

# We enable `BUNDLE_DEPLOYMENT` so that bundler won't take the liberty to upgrade any gems.
# APP_ENV for sinatra
ENV BUNDLE_DEPLOYMENT="1" \
  BUNDLE_WITHOUT="development:test:jekyll_plugins" \
  RUBYOPT='--disable-did_you_mean' \
  APP_ENV="production"

# Workdir set in base image
# hadolint ignore=DL3045
COPY --chown=app:app --from=live_builder $BUNDLE_PATH $BUNDLE_PATH
# hadolint ignore=DL3045
COPY --chown=app:app . ./

USER app

# Always refresh and save new llm model info on container start
# hadolint ignore=SC1072 # Ruby inline command, not a shell script
RUN ["ruby", "-e", "require 'bundler/setup'; Bundler.require(:default) ; RubyLLM.models.refresh! ; RubyLLM.models.save_to_json"]

ENTRYPOINT ["/usr/bin/catatonit", "--"]
CMD ["ruby", "bin/server.rb"]
