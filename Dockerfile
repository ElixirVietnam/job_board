FROM erlang:21.2-slim

ARG ELIXIR_VERSION=1.8.1

ENV LC_ALL=C.UTF-8

RUN apt-get update && apt-get install --yes wget unzip

RUN wget --no-verbose https://github.com/elixir-lang/elixir/releases/download/v$ELIXIR_VERSION/Precompiled.zip && \
unzip -qd /usr/local Precompiled.zip && \
rm Precompiled.zip

WORKDIR project

COPY mix.exs mix.lock ./

ENV MIX_ENV=prod

RUN mix local.hex --force && \
mix local.rebar --force && \
mix deps.get && \
mix deps.compile

COPY config config/
COPY lib lib/
COPY rel rel/

CMD echo "Building release for the \"$MIX_ENV\" environment" && \
mix do compile, release && \
cp _build/$MIX_ENV/rel/*/releases/*/*.tar.gz /release/ && \
echo "Done"
