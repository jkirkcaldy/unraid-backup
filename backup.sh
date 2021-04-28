#description=An incrimental backup of Unraid services. 
#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
# store your config file somewhere and enter the full path to it below
source /mnt/user/Backup/rsync-backup-config

#start here
start() {
    echo 'Starting Script'
    echo 'Checking for Autorestic install...'
    curl -s https://raw.githubusercontent.com/CupCakeArmy/autorestic/master/install.sh | bash

    if test -f "${autorestic_config}"; then
        echo "Autorestic config file exists, moving on."
    else
        echo "Autorestic config file not found. Please make sure you have created the config file and added the location to the config file."
        exit
    fi

    if [ ${power_up:-false} == true ]
    then 
        powerup
    else
        get_date
    fi
}
#Turn on the backup server
powerup() {
    echo "Waking TrueNAS Server"
    etherwake ${backup_mac}
    printf "%s" "waiting for TrueNAS ..."
    while ! timeout 0.5 ping -c 1 -n ${backup_host} &> /dev/null
    do
        printf "%c" "."
    done
        printf "\n%s\n"  "Server is online"

    # wait for 2 minutes to allow the server to finish coming online. 
    echo 'Waiting for 2 minutes for the server to finish powering up.'
    sleep 120
    get_date 
}
# Get the date
get_date(){
    echo 'getting date'
    T="$(date +%s)"
    ##Today's date
    today=$(date +"%Y%m%d")
    yesterday=$(date -d "yesterday 13:00" +'%Y%m%d')
    day=$(date +"%A")

    if [ ${nextcloud_backup:-false} == true ] 
    then
        enter_maintenance_mode
    else
        database_dump
    fi
}
# Put NextCloud into maintenance mode. 
# This ensures consistency between the database and data directory.
enter_maintenance_mode() {
    echo 'maintenance mode'
    if [ ${cloudflare:-false} == true ]
    then 
        # Maintenance mode on cloudfalre
        curl --silent -X PUT "https://api.cloudflare.com/client/v4/zones/"$zone"/workers/routes/"$route"" \
        -H "X-Auth-Email: "${email}"" \
        -H "X-Auth-Key: "${apikey}"" \
        -H "Content-Type: application/json" \
        --data '{"pattern":"'"${domain_down}"'","script":"'"${script_down}"'"}' > /dev/null
    fi
    # Nextcloud Maintenance Mode
    docker exec ${nextcloud_container:-nextcloud} /bin/sh -c "sudo -u abc php config/www/nextcloud/occ maintenance:mode --on" > /dev/null

    echo "Maintenance mode is now on"
    database_dump
}
# Dump nextcloud database
database_dump() {
    echo 'database dump'
    if [ ${nextcloud_uses_postgres:-false} == true ] | [ ${nextcloud_backup:-false} == true ]
    then
        mkdir -p ${database_dump_dir}/${today}
    fi
    if [ ${nextcloud_uses_postgres:-false} == true ] && [ ${nextcloud_backup:-false} == true ]
    then
        # Dump nextcloud database if in postgres
        echo Dumping sql database
        docker exec Postgres11 /bin/sh -c "pg_dump -U ${pdb_user} -w -d ${pdb_name} > /backup/Postgres/${today}-nextclouddb.psql"
    else
    echo 'Skipping postgres dump'
    fi
    # Dump all mysql databases
    if [ ${mysql_backup:-false} == true ] && [ ${MariaDB_backup:-false} == false ]
    then 
        databases=$(docker exec ${mysql_container} /bin/bash -c "mysql -u $db_user -p$db_passwd -e 'show databases' -s --skip-column-names" | grep -Ev "^(Database|mysql|performance_schema|information_schema)$")
        for I in ${databases}; do docker exec -i ${mysql_container} mysqldump -u${db_user} -p${db_passwd} --databases $I --skip-comments > ${database_dump_dir}/${today}/$I.sql; done
    elif [ ${MariaDB_backup:-false} == true ] && [ ${mysql_backup:-false} == false ]
    then 
        databases=$(docker exec ${MariaDB_container} /bin/bash -c "mysql -u $db_user -p$db_passwd -e 'show databases' -s --skip-column-names" | grep -Ev "^(Database|mysql|performance_schema|information_schema)$")
        for I in $databases; do docker exec -i ${MariaDB_container} mysqldump -u${db_user} -p${db_passwd} --databases $I --skip-comments > ${database_dump_dir}/${today}/$I.sql; done
    elif [ ${MariaDB_backup:-false} == true ] && [ ${mysql_backup:-false} == true ]
    then
        databases=$(docker exec ${mysql_container} /bin/bash -c "mysql -u $db_user -p$db_passwd -e 'show databases' -s --skip-column-names" | grep -Ev "^(Database|mysql|performance_schema|information_schema)$")
        for I in $databases; do docker exec -i ${mysql_container} mysqldump -u${db_user} -p${db_passwd} --databases $I --skip-comments > ${database_dump_dir}/${today}/$I.sql; done

        databases=$(docker exec ${MariaDB_container} /bin/bash -c "mysql -u $db_user -p$db_passwd -e 'show databases' -s --skip-column-names" | grep -Ev "^(Database|mysql|performance_schema|information_schema)$")
        for I in $databases; do docker exec -i ${MariaDB_container} mysqldump -u${db_user} -p${db_passwd} --databases $I --skip-comments > ${database_dump_dir}/${today}/$I.sql; done

    elif [ ${mysql_backup:-false} == false ] && [ ${MariaDB_backup:-false} == false ]
    then
        echo 'Skipping database dumps'
    fi
    
    if [ ${day} == Sunday ]
    then 
        stop_docker
    else   
        transfer
    fi
}
# Stop Dockers
stop_docker() {
    echo 'stopping docker'
    if [ ${docker_shutdown:-false} == true ] && [ ${backup_docker_appdata:-false} == true ]
    then
        running=$(docker ps --format "{{.Names}}")
        dkr=$(echo ${docker_keep_live} | sed 's=,=\\s*\\|=g')
        docker_stop=$(echo ${running} | sed "s/\(${dkr}\s*\|<END>\)//g" )
        docker stop ${docker_stop}
    fi  
    transfer 
}
#Rsync backup
transfer(){
    echo 'transfer starting...'
    # Backup nextcloud
    if [ ${nextcloud_backup:-false} == true ]
    then 
        autorestic backup -l nextcloud
    else
        echo 'Nextcloud backup set to false - skipping'
    fi

    # backup docker
    if [ ${backup_docker_appdata:-false} == true ] && [ ${day} == Sunday ]
    then 
        autorestic backup -l appdata

    elif [ ${backup_docker_appdata:-false} == true ] && [ ${day} == Sunday ]
    then
        echo 'Skipping docker backup until Sunday.'
    else
        echo 'Docker backup set to false - skipping'        
    fi

    if [ ${mysql_backup:-false} == true ] || [ ${MariaDB_backup:-false} == true ] || [ ${nextcloud_backup:-false} == true ]
    then
    echo 'copying databases'
        autorestic backup -l databases
    fi

    # Backup data directories
        autorestic backup -l backup
    backup_usb
}

# Start Docker containers again
start_dockers() {
    echo 'Starting Dockers'
    if [ ${docker_shutdown:-false} == true ]
    then
    docker start ${docker_stop}
    fi
    exit_maintenance_mode    
    #backup_usb
}
# Backup boot USB
backup_usb() {
    echo 'backing up USB'
    if [ ${backup_boot_flash:-false} == true ] 
    then
        autorestic backup -l boot
    fi

    if [ ${day} == Sunday ]
    then 
        start_dockers
    else
        exit_maintenance_mode
    fi
}

exit_maintenance_mode(){
    echo 'exit maintenance mode'
    if [ ${cloudflare:-false} == true ] 
    then
        curl --silent -X PUT "https://api.cloudflare.com/client/v4/zones/"$zone"/workers/routes/"$route"" \
        -H "X-Auth-Email: "${email}"" \
        -H "X-Auth-Key: "${apikey}"" \
        -H "Content-Type: application/json" \
        --data '{"pattern":"'"${domain_up}"'","script":"'"${script_up}"'"}' > /dev/null
        
        docker exec ${nextcloud_container} /bin/sh -c "sudo -u abc php config/www/nextcloud/occ maintenance:mode --off" > /dev/null
    elif [ ${nextcloud_backup:-false} == true ] && [ ${cloudflare:-false} == false ]
    then
        docker exec ${nextcloud_container:-nextcloud} /bin/sh -c "sudo -u abc php config/www/nextcloud/occ maintenance:mode --off" > /dev/null
    fi
    finish
}
#Finish up
finish() {
    echo 'Finishing'
    if [ ${power_off:-false} == true ]
    then
        sleep 120
        ssh ${rsync_ssh_user}@${rsync_host} "poweroff"
    fi

    date +'%a %b %e %H:%M:%S %Z %Y'
    echo 'Finished'

    T="$(($(date +%s)-T))"
    convertsecs() {
        ((h=${1}/3600))
        ((m=(${1}%3600)/60))
        ((s=${1}%60))
        printf "%02d:%02d:%02d\n" $h $m $s
    }

    echo "It took $(convertsecs ${T}) to complete"
    /usr/local/emhttp/webGui/scripts/notify -i normal -s "Backup complete. It took $(convertsecs ${T}) to complete"
}
start;  

