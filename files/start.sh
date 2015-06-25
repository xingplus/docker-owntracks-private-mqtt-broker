#!/bin/bash
#
#   Copyright 2015 Philipp Adelt
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

VOLUME=/volume
CLIENTS_DIR=$VOLUME/config/clients
PASSWD_FILE=$CLIENTS_DIR/passwd

if [ ! -d $VOLUME ]
then
   echo MISSING VOLUME. Please start container with mounted $VOLUME directory!
   exit 1;
fi

mkdir -p $VOLUME/data
mkdir -p $VOLUME/log
mkdir -p $VOLUME/config/conf.d

# Provide an initial Mosquitto config if nothing is there yet.
if [ ! -f $VOLUME/config/mosquitto.conf ]
then
   echo "Setting default configuration mosquitto.conf. Feel free to improve!"
   cp /tmp/mosquitto.conf.default $VOLUME/config/mosquitto.conf
fi

# Create a minimal CA-infrastructure with a server and 10 client certs if not there yet
if [ ! -d $VOLUME/config/tls ]
then
   echo "Generating fresh TLS/SSL infrastructure. Don't forget to install ca.crt on your devices!"
   mkdir -p $VOLUME/config/tls
   cd $VOLUME/config/tls
   /tmp/generate-CA.sh
   for ((i=1;i<=10;i++)); do
      /tmp/generate-CA.sh client$i
      PASSWORD=`pwgen --no-capitalize --numerals --ambiguous 14 1`
      echo client$i:$PASSWORD >> PASSWD_FILE
   done
   ln -s `hostname -f`.crt server.crt
   ln -s `hostname -f`.key server.key
fi

# Generate some client authentication tokens and configuration files.
if [ ! -d $CLIENTS_DIR ]
then
   echo "Generating users and client configuration files (.otrc). Open one of those with the app."
   if [ -f $VOLUME/host.config ]
   then
      . $VOLUME/host.config
   fi

   if [ "x$HOSTNAME" == "x" ] || [ "x$PORT" == "x" ] 
   then
      echo "************ PLEASE FIX host.config, then remove the config/clients/ directory and run again! ************"
      HOSTNAME="THIS.WILL.NOT.WORK.PLEASE.FIX.HOST.CONFIG.FILE.example.org"
      PORT="1883"
   fi

   mkdir -p $CLIENTS_DIR
   touch $PASSWD_FILE
   cd $CLIENTS_DIR
   
   for ((i=1;i<=10;i++)); do
      PASSWORD=`pwgen --no-capitalize --numerals --ambiguous 14 1`
      USERNAME=client$i
      echo "Username $USERNAME with Password $PASSWORD" >> $PASSWD_FILE.cleartext
      mosquitto_passwd -b $PASSWD_FILE $USERNAME $PASSWORD
      cat > $USERNAME.otrc <<EOF
{
  "ranging" : false,
  "positions" : 50,
  "monitoring" : 1,
  "willTopic" : "",
  "deviceId" : "$USERNAME",
  "host" : "$HOSTNAME",
  "tid" : "$i",
  "_type" : "configuration",
  "keepalive" : 60,
  "pubTopicBase" : "",
  "cmd" : false,
  "allowRemoteLocation" : true,
  "subTopic" : "",
  "pubRetain" : true,
  "willRetain" : false,
  "updateAddressBook" : false,
  "waypoints" : [

  ],
  "port" : $PORT,
  "pubQos" : 1,
  "locatorInterval" : 300,
  "tls" : true,
  "auth" : true,
  "cleanSession" : true,
  "extendedData" : true,
  "clientId" : "$USERNAME",
  "willQos" : 1,
  "password" : "$PASSWORD",
  "locatorDisplacement" : 2000,
  "mode" : 0,
  "subQos" : 1,
  "username" : "$USERNAME"
}
EOF
      
   done
fi

chown -R mosquitto:root $VOLUME/*
chmod -R g+wr $VOLUME/*

# Make Postgres run from the docker volume and take defaults/initial data from the "normal" locations
# Postgres gets the locations from the command line parameters in /etc/supervisord.conf .
mkdir -p $VOLUME/postgres
if [ ! -d $VOLUME/postgres/config ]
then
   echo "Postgresql: Initializing configuration in volume."
   cp -r /etc/postgresql/9.4/main $VOLUME/postgres/config
   chown -R postgres:postgres $VOLUME/postgres/config
   sed --in-place "s#/var/lib/postgresql/9.4/main#/volume/postgres/data#g" /volume/postgres/config/postgresql.conf
   sed --in-place "s#/etc/postgresql/9.4/main#/volume/postgres/config#g" /volume/postgres/config/postgresql.conf
fi
if [ ! -d $VOLUME/postgres/data ]
then
   echo "Postgresql: Initializing data in volume."
   cp -r /var/lib/postgresql/9.4/main $VOLUME/postgres/data
   chown -R postgres:postgres $VOLUME/postgres/data
fi

supervisord -n -c /etc/supervisord.conf -e debug
