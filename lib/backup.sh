#!/usr/bin/env bash

function backup_help() {
    cat <<EOT
Juggler backup CLI
Usage: app backup [OPTION]... <command>

Commands:
  init
  create [-p][-c]       Create a new backup
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

function backup_pre_init() {
    BACKUP_DIRS=$PROJECT_DIR
    BACKUP_EXCLUDE="
        $PROJECT_DIR/log
        $PROJECT_DIR/.env
    "
    BACKUP_PRUNE="--keep-within=7d --keep-weekly=4 --keep-monthly=12"
}

function backup_main() {
    TARGET_NAME="default"
    TARGET_PATH=$BACKUP_TARGET_DEFAULT
    TARGET_ENCRYPTION=$BACKUP_TARGET_DEFAULT_ENCRYPTION
    TARGET_PASSPHRASE=$BACKUP_TARGET_DEFAULT_PASSPHRASE
    # Reset the argument counter as we are calling getopts the second time
    unset OPTIND
    local help=0
    while getopts ":t:h" arg; do
        case $arg in
            t)
                # getopts ensures that $OPTARG is not empty
                targetName=$OPTARG
                eval "TARGET_PATH=\$BACKUP_TARGET_${OPTARG^^}"
                eval "TARGET_ENCRYPTION=\$BACKUP_TARGET_${OPTARG^^}_ENCRYPTION"
                eval "TARGET_PASSPHRASE=\$BACKUP_TARGET_${OPTARG^^}_PASSPHRASE"
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
    if [[ $? -ne 0 ]]; then
        echo "Invalid command: '$command'"
        backup_about_help
        exit 1
    fi

    BACKUP_REPO_DIR="$TARGET_PATH/$PROJECT_TITLE"
    LOG_DIR="$PROJECT_DIR/log"
    LOG_FILE_PATH="$LOG_DIR/backup-$(date +%y%m%d).log"
    CRON_FILE_PATH="/etc/cron.d/borgbackup-$COMPOSE_PROJECT_NAME"

    eval "cmd_backup_$command \$@"
}

function append_log() {
    # Input in a bash function is read by the first command
    sudo -u $PROJECT_DIR_USER tee -a $LOG_FILE_PATH
}

function append_logfile() {
    # Input in a bash function is read by the first command
    sudo -u $PROJECT_DIR_USER tee -a $LOG_FILE_PATH > /dev/null
}

function cmd_backup_init() {
    sudo BORG_PASSPHRASE="$TARGET_PASSPHRASE" borg init -e $TARGET_ENCRYPTION $BACKUP_REPO_DIR
}

function cmd_backup_create() {
    # Reset the argument counter as we are calling getopts the third time
    unset OPTIND
    local prune=0
    local cronjob=0
    while getopts ":pc" arg; do
        case $arg in
            p)
                prune=1
                ;;
            c)
                cronjob=1
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

    if [[ $cronjob -eq 1 && (-z $BACKUP_CRONJOB || $BACKUP_CRONJOB -ne 1) ]]; then
        echo "Cronjob backups are disabled for $PROJECT_TITLE"
        exit 0
    fi

    local timestamp=$(date +%y%m%d-%H%M)
    # Create log folder
    [[ ! -d $LOG_DIR ]] && sudo -u $PROJECT_DIR_USER mkdir $LOG_DIR

    # Ask for root to handle password failure separately
    sudo true
    if [[ $? != 0 ]]; then
        exit 1
    fi
    # Backup directories might be read protected so check with root
    sudo test -f $BACKUP_REPO_DIR/config
    if [[ $? != 0 ]]; then
        echo "FAIL ($timestamp): Borg repository not found" | append_log
        exit 0
    fi

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
        echo "INFO ($timestamp): prepare_backup is not defined" | append_logfile
    elif [[ $prepareStatus -eq 0 ]]; then
        echo "SUCCESS ($timestamp): prepare_backup completed successfully" | append_logfile
    else
        echo "FAIL ($timestamp): prepare_backup returned with exit code $prepareStatus" | append_log
    fi

    # Build exclude arguments from $BACKUP_EXCLUDE
    local exclude=""
    for pattern in $BACKUP_EXCLUDE; do
        exclude="$exclude --exclude $pattern"
    done

    echo "Starting Borg backup..."
    # Use process substitution to write logfile without lines containing CR (0x0D)
    sudo BORG_PASSPHRASE="$TARGET_PASSPHRASE" borg create --progress --stats \
        --exclude-caches $exclude \
        $BACKUP_REPO_DIR::$timestamp $BACKUP_DIRS \
        |& tee >(sed "/\x0D/d" | append_logfile)

    if [[ $prune -eq 1 ]]; then
        cmd_backup_prune
    fi    
}

function cmd_backup_prune() {
    echo "Pruning old Borg backups..."
    sudo BORG_PASSPHRASE="$TARGET_PASSPHRASE" borg prune --list --stats $BACKUP_PRUNE $BACKUP_REPO_DIR |& append_log

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

function cmd_backup_mount() {
    sudo borg mount $BACKUP_REPO_DIR::$1 $2
}

function cmd_backup_umount() {
    sudo borg umount $1
}

function cmd_backup_list() {
    sudo BORG_PASSPHRASE="$TARGET_PASSPHRASE" borg list $BACKUP_REPO_DIR
}

function cmd_backup_status() {
    local red="\033[0;31m"
    local green="\033[0;32m"
    local default="\033[0m"
    if [[ $BACKUP_CRONJOB -eq 1 ]]; then
        printf "Cron ${green}ON${default}, "
    else
        printf "Cron ${red}OFF${default}, "
    fi
    echo "last backup: $(sudo BORG_PASSPHRASE="$TARGET_PASSPHRASE" borg list --last=1 --short $BACKUP_REPO_DIR)"
    if compgen -G "$LOG_DIR/backup-*.log" > /dev/null; then
        cat $LOG_DIR/backup-*.log | grep --color=always "^FAIL \(.*\):.*"
    else
        echo "No logs found from previous backups"
    fi
}
