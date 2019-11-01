MASTER_HOSTNAME="my-docker-hostname.com"

CURRENT_DIRECTORY=$(pwd)

VARIABLE_SETUP="SETUP"
VARIABLE_START="START"
VARIABLE_STOP="STOP"
VARIABLE_REMOVE="REMOVE"

TOMCAT_CONTAINER="tomcat"
TOMCAT_PORT="1993"

ELASTICSEARCH_CONTAINER="elasticsearch"
ELASTICSEARCH_VERSION="7.4.2"
ELASTICSEARCH_PORT1="9200"
ELASTICSEARCH_PORT2="9300"

KIBANA_CONTAINER="kibana"
KIBANA_VERSION="7.4.2"
KIBANA_PORT="5601"

FILEBEAT_VERSION="7.4.2"
FILEBEAT_INDEX="server-that-filebeat-is-sitting-on.com"
FILEBEAT_CONFIG="
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/*.log
    - /home/oracle/*.out
    - /home/oracle/Oracle/Middleware/Oracle_Home/user_projects/domains/base_domain/*.log
    - /opt/apache-tomcat/bin/*.out
    - /opt/apache-tomcat/bin/*.log
    - /opt/apache-tomcat/logs/*.log
    - /opt/apache-tomcat/logs/*.out
output.elasticsearch:
  hosts: ['$MASTER_HOSTNAME:$ELASTICSEARCH_PORT1']
  index: '$FILEBEAT_INDEX'
setup:
  template:
    name: '$FILEBEAT_INDEX'
    pattern: '$FILEBEAT_INDEX-*'
  kibana:
    host: '$MASTER_HOSTNAME:$KIBANA_PORT'
  ilm:
    enabled: false
"

function main()
{
	#do_setup
	do_start
	#do_stop
	#do_remove
}

function do_setup()
{
	do_stop
	do_remove
	
	do_elasticsearch $VARIABLE_SETUP
	do_kibana $VARIABLE_SETUP
	do_tomcat $VARIABLE_SETUP
	do_filebeat $VARIABLE_SETUP
}

function do_start()
{
	do_elasticsearch $VARIABLE_START
	do_kibana $VARIABLE_START
	do_tomcat $VARIABLE_START
	do_filebeat $VARIABLE_START
}

function do_stop()
{
	do_elasticsearch $VARIABLE_STOP
	do_kibana $VARIABLE_STOP
	do_tomcat $VARIABLE_STOP
	do_filebeat $VARIABLE_STOP
}

function do_remove()
{
	do_stop 
	do_elasticsearch $VARIABLE_REMOVE
	do_kibana $VARIABLE_REMOVE
	do_tomcat $VARIABLE_REMOVE
	do_filebeat $VARIABLE_REMOVE
}

function do_tomcat()
{   
	do_docker $1 $TOMCAT_CONTAINER
}

function do_kibana()
{
	do_docker $1 $KIBANA_CONTAINER
}

function do_elasticsearch()
{
	do_docker $1 $ELASTICSEARCH_CONTAINER
}


function do_filebeat()
{
	if [ $1 == $VARIABLE_SETUP ]; then
		
		if [ -x "$(command -v rpm)" ]; then			
			FILENAME="filebeat-$FILEBEAT_VERSION-x86_64.rpm"

			if ! [ -f "$FILENAME" ]; then
				curl -L -O http://$MASTER_HOSTNAME:$TOMCAT_PORT/$FILENAME
			fi
						
			rpm -vi $FILENAME
		fi
		
		if [ -x "$(command -v dpkg)" ]; then
		
			FILENAME="filebeat-$FILEBEAT_VERSION-amd64.deb"

			if ! [ -f "$FILENAME" ]; then
				curl -L -O http://$MASTER_HOSTNAME:$TOMCAT_PORT/$FILENAME
			fi
		
			dpkg -i $FILENAME
		fi
		
		printf "$FILEBEAT_CONFIG" > /etc/filebeat/filebeat.yml

		cd /etc/filebeat/

		/usr/share/filebeat/bin/filebeat test config -e
	fi

	if [ $1 == $VARIABLE_START ]; then
		cd /etc/filebeat/
		nohup /usr/share/filebeat/bin/filebeat &> "$CURRENT_DIRECTORY/filebeat.out" &
		cd "$CURRENT_DIRECTORY"
	fi

	if [ $1 == $VARIABLE_STOP ]; then
		pkill -f filebeat
	fi

	if [ $1 == $VARIABLE_REMOVE ]; then
		ps -ea | grep filebeat | awk {'print $1'} | xargs kill -9 
		
		if [ -x "$(command -v rpm)" ]; then
			rpm -e filebeat > /dev/null
		fi
		
		if [ -x "$(command -v dpkg)" ]; then
			dpkg -r --force-all --purge filebeat
		fi
		
		rm -Rf /usr/share/filebeat
		rm -Rf /usr/share/filebeat/bin
		rm -Rf /etc/filebeat
		rm -Rf /var/lib/filebeat
		rm -Rf /var/log/filebeat
	fi
}


function do_docker()
{
	if ! [ -x "$(command -v docker)" ]; then
		return
	fi

	if [ $1 == $VARIABLE_SETUP ]; then

		if [ $2 == $KIBANA_CONTAINER ]; then
			# https://www.elastic.co/guide/en/kibana/current/docker.html
			docker run -d --name $KIBANA_CONTAINER \
						  --link $ELASTICSEARCH_CONTAINER:elasticsearch \
						  -p $KIBANA_PORT:5601 \
						  docker.elastic.co/kibana/kibana:$KIBANA_VERSION \
		
		fi

		if [ $2 == $ELASTICSEARCH_CONTAINER ]; then
			# https://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html
			docker run -d --name $ELASTICSEARCH_CONTAINER -p $ELASTICSEARCH_PORT1:9200 \
														  -p $ELASTICSEARCH_PORT2:9300 \
														  -e "discovery.type=single-node" \
														  docker.elastic.co/elasticsearch/elasticsearch:$ELASTICSEARCH_VERSION \
		
		fi

		if [ $2 == $TOMCAT_CONTAINER ]; then
			docker run -d --name tomcat -p $TOMCAT_PORT:8080 tomcat:latest

			TOMCAT_WEBAPPS_DIR="//usr/local/tomcat/webapps"

			ELASTIC_DOMAIN="https://artifacts.elastic.co/downloads/beats/filebeat"

			docker exec -t $TOMCAT_CONTAINER bash -c "rm -Rf $TOMCAT_WEBAPPS_DIR/*"
			docker exec -t $TOMCAT_CONTAINER bash -c "mkdir $TOMCAT_WEBAPPS_DIR/ROOT"
			docker exec -t $TOMCAT_CONTAINER bash -c "chmod 755 $TOMCAT_WEBAPPS_DIR/ROOT"
			docker exec -t $TOMCAT_CONTAINER bash -c "cd $TOMCAT_WEBAPPS_DIR/ROOT && curl -L -O $ELASTIC_DOMAIN/filebeat-$FILEBEAT_VERSION-amd64.deb"
			docker exec -t $TOMCAT_CONTAINER bash -c "cd $TOMCAT_WEBAPPS_DIR/ROOT && curl -L -O $ELASTIC_DOMAIN/filebeat-$FILEBEAT_VERSION-x86_64.rpm"
		fi

	fi

	if [ $1 == $VARIABLE_START ]; then
		docker start $2
	fi

	if [ $1 == $VARIABLE_STOP ]; then
		docker stop $2
	fi

	if [ $1 == $VARIABLE_REMOVE ]; then
		docker rm $2
	fi
}

function do_OracleContainer_Startup()
{
	#For Oracle Docker Containers
	echo 'CURRENT_DIRECTORY=$(pwd)' >> //opt/oracle/scripts/startup/custom_startup.sh
	echo 'cd //etc/filebeat/' >> //opt/oracle/scripts/startup/custom_startup.sh
	echo "echo password | su -c \"/usr/share/filebeat/bin/filebeat &\"" >> //opt/oracle/scripts/startup/custom_startup.sh
	echo 'cd "$CURRENT_DIRECTORY"' >> //opt/oracle/scripts/startup/custom_startup.sh
}

main
