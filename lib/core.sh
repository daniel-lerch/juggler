#!/usr/bin/env bash

function init() {
    local directory=$1
    PROJECT_NAME=${directory:5} # substring at 5 to remove /opt/
    COMPOSE_FILE="$directory/docker-compose.yml"
    COMPOSE_PROJECT_NAME=
    APP_CONTAINER_NAME="$COMPOSE_PROJECT_NAME-app"
}

function invoke_composer() {
    # TODO: Omit sudo if not required
    sudo docker-compose -f $COMPOSE_FILE -p $COMPOSE_PROJECT_NAME $@
}
