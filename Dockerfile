# Development image for the decidim-frontdoors module: the test application
# (spec/decidim_dummy_app), the development application (development_app) and
# the specs all run in it.
#
# Ruby and Node are pinned to the exact versions Decidim 0.32.2 pins in its
# own .ruby-version and .node-version. When bumping them, keep those two files
# in the repository root in sync with the ARGs below.

ARG RUBY_VERSION=3.4.7
ARG NODE_VERSION=22.14.0
ARG DEBIAN_RELEASE=bookworm

FROM node:${NODE_VERSION}-${DEBIAN_RELEASE}-slim AS node

FROM ruby:${RUBY_VERSION}-slim-${DEBIAN_RELEASE} AS base

ARG BUNDLER_VERSION=2.6.9
# Upstream ImageMagick and libvips versions; the trailing wildcard only lets
# Debian's own security revisions (deb12uN) through.
ARG IMAGEMAGICK_VERSION=8:6.9.11.60+dfsg-1.6+deb12u*
ARG LIBVIPS_VERSION=8.14.1-3+deb12u*
# Overridden from .env by compose so files written to the bind mount belong to
# the host user instead of root.
ARG APP_UID=1000
ARG APP_GID=1000

# Keeps Bundler on the pinned version instead of switching to whatever a
# lockfile was last written with.
ENV BUNDLER_VERSION=${BUNDLER_VERSION}

# build-essential, pkg-config and the -dev packages compile native gems
# (charlock_holmes needs ICU, psych needs libyaml); git is used by Bundler and
# the Decidim generator; tzdata by Rails time zones. Decidim 0.32 requires
# libvips next to ImageMagick: the app does not boot without it.
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      pkg-config \
      libicu-dev \
      libpq-dev \
      libssl-dev \
      libyaml-dev \
      zlib1g-dev \
      tzdata \
      "imagemagick=${IMAGEMAGICK_VERSION}" \
      "libvips42=${LIBVIPS_VERSION}" \
      "libvips-tools=${LIBVIPS_VERSION}" \
 && rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

RUN gem install bundler --version "${BUNDLER_VERSION}" --no-document

RUN groupadd --non-unique --gid "${APP_GID}" app \
 && useradd --non-unique --uid "${APP_UID}" --gid "${APP_GID}" --create-home --shell /bin/bash app \
 && mkdir -p /app \
 && chown -R app:app /app "${GEM_HOME}"

# The browser the system specs drive (decidim-dev's headless Chrome), with its
# driver. Debian's security updates move Chromium to a new major version every
# few weeks and drop the old one, so only the major is pinned: when Debian
# moves on, the build stops here and the number is raised by hand.
ARG CHROMIUM_VERSION=156.*
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      "chromium=${CHROMIUM_VERSION}" \
      "chromium-driver=${CHROMIUM_VERSION}" \
 && rm -rf /var/lib/apt/lists/*

# Selenium uses this driver as it is, instead of looking for one to download.
ENV SE_CHROMEDRIVER=/usr/bin/chromedriver

USER app
WORKDIR /app

# The gems are not in the image: they live in the "bundle" volume of
# compose.yaml, because generating the development application installs a few
# more than Gemfile.lock holds. `docker compose run --rm app bundle install`
# fills it.
CMD ["bash"]
