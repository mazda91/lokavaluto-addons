#!/bin/sh

ROOT_DIR=$(pwd)

DATA_ONLY=0
for i in "$@"
do
    case $i in
        -e|--env)
            ENV="$2"
            shift #past argument
            shift #past value
            ;;
        -d|--data-only)
            DATA_ONLY=1
            shift
            ;;
        -h|--help)
            echo "Generates scripts to initialize docker services and containers with a dev/test dataset \n"
            echo "WARNING : This script should never be executed in a production context \n"
            echo "Usage:  --env ENV [--data-only] \n"
            echo "Options: \r"
            echo "    -e, --env          Set environment variable. It can be either dev/test. \r"
            echo "    -d, --data-only    Delete then generate dataset only instead of all services and docker containers. \r"
            echo "    -h, --help         Show this prompt with a list of options. \r"
            exit 0
            ;;
    esac
done

if [ "$ENV" = "dev" -o "$ENV" = "test" ]; then
    #analyse de la commande

    #if config to generate
    if [ "$DATA_ONLY" = "0" ]; then
        if [ "$ENV" = "dev" ]; then
            OTHER_ENV="test"
        else
            OTHER_ENV="dev"
        fi

        if [ -f ./etc/cyclos/cyclos_constants_$ENV.yml ] || [ ! -f ./etc/cyclos/cyclos_constants_$OTHER_ENV.yml ]; then
            read -p "You are about to regenerate all the docker services. Are you sure? (y/n)" response

            if [ -z $response ]; then
                response="n"
                echo "To regenerate dataset only, use -d option"
            fi

            while [ $response != "y" ] && [ $response != "n" ]; do
                read -p "You are about to regenerate all the docker services. Are you sure? (y/n)" response
            done

            if [ $response = "n" ]; then
                exit 0
            fi

            echo "$(tput setaf 3) Delete cyclos data... $(tput sgr 0)"
            rm -rf data/cyclos
            rm -f etc/cyclos/cyclos_constants_$ENV.yml
            rm -f etc/cyclos/cyclos_constants_$OTHER_ENV.yml
            echo "$(tput setaf 2) Delete cyclos data... OK ! "

            sleep 2
            echo "$(tput setaf 3) Stop and remove containers, networks and volumes...  $(tput sgr 0)"
            docker-compose down -v
            echo "$(tput setaf 2)  Stop and remove containers, networks and volumes... OK !"

            sleep 2

            echo "$(tput setaf 3) (Re)create cyclos database container from cyclos-db service $(tput sgr 0)"
            docker-compose up -d cyclos-db

            echo "INFO : Wait for cyclos init process to finish initial dump. It should take up to 3mins \n"
            echo "HINT : In order to check progression, input sudo docker-compose logs -f cyclos-db in another terminal \n"
            docker logs cyclos-db 2>&1  | grep -Pzl '(?s)init process complete.*\n.*ready to accept connections'
            while [ $? -ne 0 ]; do
                sleep 5;
                #this must be the last line of the while loop
                docker logs cyclos-db 2>&1  | grep -Pzl '(?s)init process complete.*\n.*ready to accept connections'
            done

            echo "$(tput setaf 2)  (Re)create cyclos database container from cyclos-db service... OK !"
            sleep 2

            docker-compose up -d cyclos-app

            sleep 2
            docker-compose up -d odoo

            echo "wait for odoo postgres database to finish process after startup"
            docker logs postgres_odoo 2>&1  | grep -Pzl '(?s)init process complete'
            while [ $? -ne 0 ]; do
                sleep 5;
                #this must be the last line of the while loop
                docker logs postgres_odoo 2>&1  | grep -Pzl '(?s)init process complete'
            done

            ## Update postgres password
            docker-compose exec -T postgres bash -c \
                'PGUSER=postgres psql <<<"ALTER USER postgres WITH ENCRYPTED password "'\\\''$POSTGRES_ROOT_PASSWORD'\\\'

            ## Set pg_hba.conf
            docker-compose exec -T postgres bash -c '
            PG_HBA=/var/lib/postgresql/data/pg_hba.conf
            if ! grep -E "^host all all (0.0.0.0/0|all) md5\$" "$PG_HBA" >/dev/null 2>&1; then
                if grep -E "^host all all (0.0.0.0/0|all) trust\$" "$PG_HBA" >/dev/null 2>&1; then
                    sed -ri '\''s%^host all all (0\.0\.0\.0/0|all) trust$%host all all \1 md5%g'\'' \
                        "$PG_HBA"
                    echo "Accepting connection from outside."
                else
                    echo "Can'\''t ensure connection from outside." >&2
                    exit 1
                fi
            fi
            '

            if [ "$?" != 0 ]; then
                echo "Error: can't update pg_hba.conf" >&2
            else
                docker-compose restart postgres
            fi

            sleep 5
            docker-compose exec -T postgres bash -c \
                'PGUSER=postgres createdb $PG_DATABASE'

            docker-compose exec -T postgres bash -c \
                'PGUSER=postgres psql $PG_DATABASE -c "CREATE EXTENSION IF NOT EXISTS unaccent;"'

            docker-compose exec -T postgres bash -c \
                'PGUSER=postgres psql <<<"CREATE USER \"$PG_USER\" WITH PASSWORD '\''$PG_PASS'\'' CREATEDB NOCREATEROLE;"'

            docker-compose exec -T postgres bash -c \
                'PGUSER=postgres prefix_pg_local_command=" " pgm chown $PG_USER $PG_DATABASE'

        fi

        echo "$(tput setaf 3) Generate cyclos configuration and initial data... $(tput sgr 0)"
        docker-compose exec  -e ENV=$ENV cyclos-app sh /cyclos/setup_cyclos.sh
        echo "$(tput setaf 2)  Generate cyclos configuration and initial data... OK !"

    else
        if [ -f ./etc/cyclos/cyclos_constants_$ENV.yml ]; then
            echo "$(tput setaf 3) Clean cyclos database from all users, payments and accounts data... $(tput sgr 0)"
            sleep 2
            docker-compose exec -T cyclos-db psql -v network="'%$ENV%'" -U cyclos cyclos < etc/cyclos/script_clean_database.sql
            echo "$(tput setaf 2) Clean cyclos database from all users, payments and accounts data... OK !"
            sleep 2
            echo "$(tput setaf 3) Regenerate cyclos init data : users, accounts credit and payments ... $(tput sgr 0)"
            sleep 2
            docker-compose exec -T  -e ENV=$ENV cyclos-app python3 /cyclos/init_test_data.py http://cyclos-app:8080/ YWRtaW46YWRtaW4=
            echo "$(tput setaf 2) Regenerate cyclos init data : users, accounts credit and payments... OK !"
        else
            echo "Cyclos constants file not found for $ENV mode. The cyclos containers and configuration have not been settled. \n Remove -d option from the command"
            exit 0
        fi
    fi
else
    echo "choose dev / test as a script variable"
    exit 1
fi
