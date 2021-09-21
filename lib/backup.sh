#!/usr/bin/env bash

function backup_help() {
    cat <<EOT
Juggler backup CLI
Usage: app backup [OPTION]... <command>

Commands:
  init
  register
  deregister
  run [--prune]         Create a new backup
  prune                 Delete old backups
  mount <tag> <path>    Mounts an archive at the specified location
  umount <path>
  list
  status                Show last backup and cron job status

Options:
  -t                    Name of the target repository location
  -h                    Show this help message
EOT
}

function backup_about_help() {
    echo "Run app backup -h for more information."
}

function backup_main() {
    TARGET_NAME="default"
    TARGET_PATH=$BACKUP_TARGET_DEFAULT
    TARGET_ENCRYPTION=$BACKUP_TARGET_DEFAULT_ENCRYPTION
    TARGET_PASSPHRASE=$BACKUP_TARGET_DEFAULT_PASSPHRASE
    local help=0
    while getopts ":t:h" arg; do
        case $arg in
            t)
                # getopts ensures that $OPTARG is not empty
                targetName=$OPTARG
                eval "TARGET_PATH=\$BACKUP_TARGET_${OPTARG^^}"
                eval "TARGET_ENCRYPTION=\$_BACKUP_TARGET_${OPTARG^^}_ENCRYPTION"
                eval "TARGET_PASSPHRASE=\$_BACKUP_TARGET_${OPTARG^^}_PASSPHRASE"
                if [[ -z $TARGET_PATH ]]; then
                    echo "Invalid backup target: '$OPTARG'"
                    exit 1
                fi
                ;;
            h)
                help=1
                ;;
            \?)
                echo "Invalid option: '$OPTARG'"
                backup_about_help
                exit 1
                ;;
            :)
                echo "Invalid option: '$OPTARG' requires an argument"
                backup_about_help
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [[ $help == 1 ]]; then
        backup_help
        exit 0
    fi

    local command=$1
    shift

    declare -F "cmd_backup_$command" > /dev/null
    if [[ $? != 0 ]]; then
        echo "Invalid command: '$command'"
        about_help
        exit 1
    fi

    BACKUP_REPO_DIR="$TARGET_PATH/$PROJECT_TITLE"
    LOG_DIR="$PROJECT_DIR/log"
    LOG_FILE_PATH="$LOG_DIR/backup-$(date +%y%m%d).log"
    CRON_FILE_PATH="/etc/cron.d/borgbackup-$COMPOSE_PROJECT_NAME"

    eval "cmd_backup_$command" "$@"
}

function cmd_backup_init() {
    sudo BORG_PASSPHRASE="$TARGET_PASSPHRASE" borg init -e $TARGET_ENCRYPTION $BACKUP_REPO_DIR
}

function cmd_backup_register() {
    # Get random minute between 0 and 59 to prevent backups from running all at once
    local minute=$(shuf -i 0-59 -n 1)
}

function cmd_backup_run() {
    # Create log folder
    [[ ! -d $LOG_DIR ]] && mkdir $LOG_DIR
    local prepareStatus=0
    # Check if function prepare_backup() is defined
    declare -F "prepare_backup" > /dev/null
    if [[ $? == 0 ]]; then
        echo "Preparing for backup..." | sudo tee -a $LOG_FILE_PATH
        prepare_backup |& sudo tee -a $LOG_FILE_PATH
        prepareStatus=${PIPESTATUS[0]}
    elif [[ ! -z $MYSQL_DATABASE && ! -z $MYSQL_ROOT_PASSWORD ]]; then
        echo "Automatically writing MySQL dump..." \
            | sudo tee -a $LOG_FILE_PATH
        invoke_composer exec -T db \
            mysqldump --single-transaction \
            -h localhost -u root -p$MYSQL_ROOT_PASSWORD $MYSQL_DATABASE \
            --result-file=/var/opt/backup/$MYSQL_DATABASE.sql \
            |& sudo tee -a $LOG_FILE_PATH
        prepareStatus=${PIPESTATUS[0]}
    fi

    # TODO: Log success
    # TODO: Perform actual backup
}
