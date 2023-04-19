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
  ps

Modules:
  backup        Invoke Borg and manage backups

EOT
}

function core_init() {
    # Initialize variables
    PROJECT_DIR=$1
    PROJECT_DIR_UID=$(stat -c "%U" $PROJECT_DIR)
    PROJECT_DIR_GID=$(stat -c "%G" $PROJECT_DIR)
    PROJECT_NAME=$(basename $PROJECT_DIR)
    if [[ $ENABLE_PROJECT_GROUPS -ne 1 ]]; then
        PROJECT_TITLE=$PROJECT_NAME
        PROJECT_FULLNAME=$PROJECT_NAME
    else
        local group_directory=$(dirname $PROJECT_DIR)
        PROJECT_GROUP=$(basename $group_directory)
        PROJECT_TITLE="$PROJECT_GROUP/$PROJECT_NAME"
        PROJECT_FULLNAME="$PROJECT_GROUP-$PROJECT_NAME"
    fi

    local composeModule=0
    if [[ -e "$PROJECT_DIR/docker-compose.yml" ]]; then
        source "$JUGGLER_LIB/compose.sh"
        compose_pre_init
        composeModule=1
    fi
    local backupModule=0
    declare -F "cmd_backup" > /dev/null
    if [[ $? -eq 0 ]]; then
        source "$JUGGLER_LIB/backup.sh"
        backup_pre_init
        backupModule=1
    fi

    # Load include file with custom functions
    if [[ -e "$PROJECT_DIR/juggler.sh" ]]; then
        source "$PROJECT_DIR/juggler.sh"
    fi

    if [[ composeModule -eq 1 ]]; then
        compose_post_init
    fi
    #if [[ backupModule -eq 1 ]]; then
    #    backup_post_init
    #fi
}

function core_load_config() {
    # Traverse folders to find config first
    try_find_config $1
    if [[ -z $JUGGLER_CONFIG_FILE ]]; then
        echo "No Juggler config file found in this directory or its parents and The JUGGLER_CONFIG_FILE variable is not set. Backup features have been disabled."
    else
        if [[ ! -e $JUGGLER_CONFIG_FILE ]]; then
            echo "No Juggler config file found at $JUGGLER_CONFIG_FILE"
            exit 1
        fi
        source $JUGGLER_CONFIG_FILE
        if [[ -z $BACKUP_TARGET_DEFAULT ]] || [[ -z $BACKUP_TARGET_DEFAULT_ENCRYPTION ]]; then
            echo "The default backup target is no specified correctly."
            exit 1
        fi
        function cmd_backup() {
            backup_main $@
        }
    fi
}

function try_find_config() {
    local workdir=$1
    while true; do
        if [[ $workdir == "/" ]]; then
            break
        elif [[ -e "$workdir/juggler_config.sh" ]]; then
            JUGGLER_CONFIG_FILE=$workdir/juggler_config.sh
            break
        else
            workdir=$(dirname $workdir)
        fi
    done
}
