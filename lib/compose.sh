#!/usr/bin/env bash

# Docker Compose module of Juggler

function compose_pre_init() {
    COMPOSE_PROJECT_NAME="$PROJECT_FULLNAME"
    COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
    APP_CONTAINER_NAME="$COMPOSE_PROJECT_NAME-app"
}

function compose_post_init() {
    # Read all necessary variables from docker-compose.yml and add them to the environment file
    local composeVariables=$(/opt/juggler/lib/python/list_compose_variables.py $COMPOSE_FILE)
    if [[ ! -z $composeVariables ]]; then
        cat > "$PROJECT_DIR/.env" <<EOT
# This file was generated by Juggler. Do not edit.
# Make your changes in juggler.sh instead.

EOT
        chown $PROJECT_DIR_UID:$PROJECT_DIR_GID "$PROJECT_DIR/.env"
        for variable in $composeVariables; do
            eval "local value=\${$variable}"
            echo $variable=$value >> "$PROJECT_DIR/.env"
        done
    fi

    if [[ ! -z $MYSQL_DATABASE && ! -z $MYSQL_USER && ! -z $MYSQL_PASSWORD ]]; then
        compose_ext_mysql
    fi
}

function invoke_composer() {
    echo "invoke_composer is deprecated. Use invoke_compose instead"
    invoke_compose $@
}

function invoke_compose() {
    # Split declaration and assignment: https://superuser.com/a/1103711/1170601
    local composeCommand
    if ! composeCommand=$(/opt/juggler/lib/python/docker_compose_command.py $DOCKER_CONTEXT); then
        echo $composeCommand
        exit 1
    fi
    $composeCommand -f $COMPOSE_FILE --env-file "$PROJECT_DIR/.env" -p $COMPOSE_PROJECT_NAME $@
}

function cmd_up() {
    if [[ $1 == "-f" ]]; then
        invoke_compose down
    fi

    invoke_compose up -d
}

function cmd_down() {
    invoke_compose down
}

function cmd_update() {
    if [[ $1 == "-r" ]]; then
        local recreate=1
        shift
    fi

    declare -F update_images > /dev/null
    if [[ $? == 0 ]]; then
        update_images $@
    else
        invoke_compose pull
    fi

    if [[ $recreate == 1 ]]; then
        invoke_compose up -d
    fi
}

function cmd_start() {
    invoke_compose start $@
}

function cmd_restart() {
    invoke_compose restart $@
}

function cmd_stop() {
    invoke_compose stop $@
}

function cmd_exec() {
    invoke_compose exec app bash
}

function cmd_logs() {
    invoke_compose logs -f app
}

function cmd_ps() {
    invoke_compose ps
}

function compose_ext_mysql() {
    declare -F "cmd_execdb" > /dev/null
    if [[ $? != 0 ]]; then
        function cmd_execdb() {
            invoke_compose exec db mysql -h localhost -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE
        }
    fi
}
