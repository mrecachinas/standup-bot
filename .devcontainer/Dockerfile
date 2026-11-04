# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.2
FROM ghcr.io/rails/devcontainer/images/ruby:$RUBY_VERSION

# Debian 13 moved backward-compatible zone names (e.g. America/Godthab, which
# Microsoft::WindowsTimeZones uses) out of tzdata.
RUN sudo apt-get update -qq && \
    sudo apt-get install --no-install-recommends -y tzdata-legacy && \
    sudo rm -rf /var/lib/apt/lists/*
