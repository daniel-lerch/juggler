#!/usr/bin/env bash

function backup_help() {
    cat <<EOT
Juggler backup CLI
Usage: app backup [OPTION]... <command>

Commands:
  init
  register
  deregister
  create [--prune]      Create a new backup
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
    LOG_USER=$(stat -c "%U" $PROJECT_DIR)

    eval "cmd_backup_$command" "$@"
}

function append_log() {
    # Input in a bash function is read by the first command
    sudo -u $LOG_USER tee -a $LOG_FILE_PATH
}

function append_logfile() {
    # Input in a bash function is read by the first command
    sudo -u $LOG_USER tee -a $LOG_FILE_PATH > /dev/null
}

function cmd_backup_init() {
    sudo BORG_PASSPHRASE="$TARGET_PASSPHRASE" borg init -e $TARGET_ENCRYPTION $BACKUP_REPO_DIR
}

function cmd_backup_register() {
    # Get random minute between 0 and 59 to prevent backups from running all at once
    local minute=$(shuf -i 0-59 -n 1)
    local command="/opt/juggler/bin/app backup create --prune"
    echo "# Juggler cron job to backup $PROJECT_TITLE
$minute 3 * * * root $command" | sudo tee $CRON_FILE_PATH > /dev/null
    echo "Registered cron job for $APPS_TITLE"
}

function cmd_backup_deregister() {
    if [[ -e $CRON_FILE_PATH ]]; then
        sudo rm $CRON_FILE_PATH
        echo "Removed cron job for $APPS_TITLE"
    else
        echo "No cron job found for $APPS_TITLE"
    fi
}

function cmd_backup_create() {
    # Create log folder
    [[ ! -d $LOG_DIR ]] && sudo -u $LOG_USER mkdir $LOG_DIR
    # Check if function prepare_backup() is defined
    declare -F "prepare_backup" > /dev/null
    if [[ $? == 0 ]]; then
        echo "Preparing for backup..." | append_log
        prepare_backup |& append_log
        local prepareStatus=${PIPESTATUS[0]}
    elif [[ ! -z $MYSQL_DATABASE && ! -z $MYSQL_ROOT_PASSWORD ]]; then
        echo "Automatically writing MySQL dump..." \
            | append_log
        invoke_composer exec -T db \
            mysqldump --single-transaction \
            -h localhost -u root -p$MYSQL_ROOT_PASSWORD $MYSQL_DATABASE \
            --result-file=/var/opt/backup/$MYSQL_DATABASE.sql \
            |& append_log
        local prepareStatus=${PIPESTATUS[0]}
    fi

    # Log failure message for easy usage in scripts
    if [[ -z ${prepareStatus+x} ]]; then
        # Substitutes unset variable to null and everything else to x
        echo "INFO ($(date +%y%m%d-%H%M)): prepare_backup is not defined" | append_logfile
    elif [[ $prepareStatus -eq 0 ]]; then
        echo "SUCCESS ($(date +%y%m%d-%H%M)): prepare_backup completed successfully" | append_logfile
    else
        echo "FAIL ($(date +%y%m%d-%H%M)): prepare_backup returned with exit code $prepareStatus" | append_log
    fi

    # TODO: Perform actual backup
}

function cmd_backup_prune() {
    # TODO: Implement backup prune
    
    # Delete old logfiles after one month
    local threshold=$(date --date="last month" +%y%m%d)
    for file in $LOG_DIR/backup-*.log; do
        local filename=$(basename $file)
        local filedate=${filename:7:6} # Substring at offset 7 with length 6 (get numbers only)
        if [[ -e $file && $threshold -gt $filedate ]]; then
            sudo rm $file
            echo "Deleted $file"
        fi
    done
}

function cmd_backup_list() {
    sudo BORG_PASSPHRASE="$TARGET_PASSPHRASE" borg list $BACKUP_REPO_DIR
}

function cmd_backup_status() {
    local red="\033[0;31m"
    local green="\033[0;32m"
    local default="\033[0m"
    if [[ -e $CRON_FILE_PATH ]]; then
        printf "Cron ${green}ON${default}, "
    else
        printf "Cron ${red}OFF${default}, "
    fi
    echo "last backup: $(sudo BORG_PASSPHRASE="$TARGET_PASSPHRASE" borg list --last=1 --short $BACKUP_REPO_DIR)"
    cat $LOG_DIR/backup-*.log | grep --color=always "^FAIL \(.*\):.*"
}
