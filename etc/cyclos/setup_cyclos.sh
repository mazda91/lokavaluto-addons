#!/bin/bash
set -e

WORKDIR=$(pwd)

cd /cyclos


until [ `curl --silent --write-out '%{response_code}' -o /dev/null http://cyclos-app:8080/global/` -eq 200 ];
do
  echo '--- waiting for Cyclos to be fully up (10 seconds)'
  sleep 10
done

if [ ! -f ./cyclos_constants_$ENV.yml ]; then
    read -p "Global Admin Login?" login
    read -p "Global Admin password?" password

    PASS=`echo -n $login:$password | base64`

    python3 setup.py http://cyclos-app:8080/ $PASS
    sleep 5
    python3 init_test_data.py http://cyclos-app:8080/ $PASS
fi

cd ${WORKDIR}

exec "$@"


# This is how I launch this script (in dev):
# docker-compose exec api bash /cyclos/setup_cyclos.sh

# This cd will do this: cd /cyclos/
#~ cd "${0%/*}"
#~
#~ echo $PWD
#~
#~ rm -f cyclos_constants.yml
#~
#~ # Base64('admin:admin') = YWRtaW46YWRtaW4=
#~ python setup.py http://cyclos-app:8080/ YWRtaW46YWRtaW4=
#~ python init_static_data.py http://cyclos-app:8080/ YWRtaW46YWRtaW4=
