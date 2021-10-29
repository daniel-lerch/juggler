#!/usr/bin/env bash

function core_commands_overview() {
    cat <<EOT
Commands:
  up [-f]       Create containers and start them
  down          Stop and delete containers
  update [-r]   Build or pull images
  start
  restart
  stop
  exec
  logs

Modules:
  backup        Invoke Borg and manage backups

EOT
}

function core_init() {
    core_load_config
    # Initialize variables
    PROJECT_DIR=$1
    PROJECT_NAME=$(basename $PROJECT_DIR)
    local group_directory=$(dirname $PROJECT_DIR)
    PROJECT_GROUP=$(basename $group_directory)
    PROJECT_TITLE="$PROJECT_GROUP/$PROJECT_NAME"
    PROJECT_FULLNAME="$PROJECT_GROUP-$PROJECT_NAME"

    local composeModule=0
    if [[ -e "$PROJECT_DIR/docker-compose.yml" ]]; then
        source "/opt/juggler/lib/compose.sh"
        compose_pre_init
        composeModule=1
    fi
    #source "/opt/juggler/lib/backup.sh"

    # Load include file with custom functions
    if [[ -e "$PROJECT_DIR/juggler.sh" ]]; then
        source "$PROJECT_DIR/juggler.sh"
    fi

    if [[ composeModule -eq 1 ]]; then
        compose_post_init
    fi
}

function core_load_config() {
    if [[ -z $JUGGLER_CONFIG_FILE ]]; then
        echo "The JUGGLER_CONFIG_FILE variable is not set"
        exit 1
    elif [[ ! -e $JUGGLER_CONFIG_FILE ]]; then
        echo "No Juggler config file found at $JUGGLER_CONFIG_FILE"
        exit 1
    fi
    source $JUGGLER_CONFIG_FILE
}
