function apply_yaml()
{
	kubectl apply -f srcs/$@.yaml > /dev/null
	printf "Deploying $@\n"
	sleep 2;
	while [[ $(kubectl get pods -l app=$@ -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
		sleep 1;
	done
	printf "Successfully deployed $@\n"
}


SERVICE_LIST="nginx influxdb grafana mysql phpmyadmin wordpress ftps telegraf"

if [[ $1 = 'clean' ]]
then
	printf "Cleaning all services...\n"
	for SERVICE in $SERVICE_LIST
	do
		kubectl delete -f srcs/$SERVICE.yaml > /dev/null
	done
	kubectl delete -f srcs/ingress.yaml > /dev/null
	printf "Clean complete !\n"
	exit
fi

if [[ $(minikube status | grep -c "Running") == 0 ]]
then
	if [[ "$OSTYPE" == "darwin"* ]]
	then
		minikube start --cpus=2 --memory 4000 --vm-driver=virtualbox --extra-config=apiserver.service-node-port-range=1-35000
	elif [[ "$OSTYPE" == "linux"* ]]
	then
#		Run the below file if not installed yet on your vm
#		bash srcs/utils/pastebin.sh
		sudo chmod 666 /var/run/docker.sock <<< user42
		minikube start --cpus=2 --memory 4000 --vm-driver=docker --extra-config=apiserver.service-node-port-range=1-35000
	fi
	minikube addons enable metrics-server
	minikube addons enable ingress
	minikube addons enable dashboard
fi

MINIKUBE_IP=$(minikube ip)
WORK_DIR=$(pwd)

# Set the docker images in Minikube

eval $(minikube docker-env)

# Set up already built database, the reset user/pass is for safety as it is sometimes required
echo "UPDATE data_source SET url = 'http://$MINIKUBE_IP:8086'" | sqlite3 srcs/grafana/grafana.db
echo "update user set password = '59acf18b94d7eb0694c61e60ce44c110c7a683ac6a8f09580d626f90f4a242000746579358d77dd9e570e83fa24faa88a8a6', salt = 'F3FAxVm33R' where login = 'admin'; exit" | sqlite3 srcs/grafana/grafana.db

# SED command is bad for portability

clang++ -o sed_maison srcs/utils/sed.cpp

#sed -i '' "s/MINIKUBE_IP/$MINIKUBE_IP/g" srcs/telegraf.yaml
#sed -i '' "s/MINIKUBE_IP/$MINIKUBE_IP/g" srcs/wordpress/files/wordpress.sql
#sed -i '' "s/MINIKUBE_IP/$MINIKUBE_IP/g"srcs/ftps/scraipts/start.sh
#sed -i '' "s/MINIKUBE_IP/$MINIKUBE_IP/g"srcs/grafana/dashboards_backup/datasources.yml
./sed_maison srcs/telegraf.yaml "MINIKUBE_IP" "$MINIKUBE_IP"
./sed_maison srcs/wordpress/files/wordpress.sql "MINIKUBE_IP" "$MINIKUBE_IP"
./sed_maison srcs/ftps/scripts/start.sh "MINIKUBE_IP" "$MINIKUBE_IP"
./sed_maison srcs/grafana/dashboards_backup/datasources.yml "MINIKUBE_IP" "$MINIKUBE_IP"


docker build -t influxdb srcs/influxdb
docker build -t mysql srcs/mysql
docker build -t wordpress srcs/wordpress
docker build -t nginx srcs/nginx
docker build -t phpmyadmin srcs/phpmyadmin
docker build -t ftps srcs/ftps
docker build -t telegraf srcs/telegraf
docker build -t grafana srcs/grafana

for SERVICE in $SERVICE_LIST
do
	apply_yaml $SERVICE
done

kubectl apply -f srcs/ingress.yaml > /dev/null

kubectl exec -i $(kubectl get pods | grep mysql | cut -d" " -f1) -- mysql -u root -e 'CREATE DATABASE wordpress;'
kubectl exec -i $(kubectl get pods | grep mysql | cut -d" " -f1) -- mysql wordpress -u root < srcs/wordpress/files/wordpress.sql

# RESETS
#sed -i '' "s/$MINIKUBE_IP/MINIKUBE_IP/g" srcs/telegraf.yaml
#sed -i '' "s/$MINIKUBE_IP/MINIKUBE_IP/g" srcs/wordpress/files/wordpress.sql
#sed -i '' "s/$MINIKUBE_IP/MINIKUBE_IP/g"srcs/ftps/scripts/start.sh
#sed -i '' "s/$MINIKUBE_IP/MINIKUBE_IP/g"srcs/grafana/dashboards_backup/datasources.yml
./sed_maison srcs/telegraf.yaml "$MINIKUBE_IP" "MINIKUBE_IP"
./sed_maison srcs/ftps/scripts/start.sh "$MINIKUBE_IP" "MINIKUBE_IP"
./sed_maison srcs/wordpress/files/wordpress.sql "$MINIKUBE_IP" "MINIKUBE_IP"
./sed_maison srcs/grafana/dashboards_backup/datasources.yml "$MINIKUBE_IP" "MINIKUBE_IP"

rm sed_maison

echo ""
echo "---"
echo "IP: $MINIKUBE_IP"
echo ""
echo "Logins:"
echo "wp: admin/admin user1/admin ..."
echo "php: root/password"
echo "grafana: admin/admin"
echo "ftps: admin/admin"
echo ""
echo "SERVICES:"
echo "ssh: 4000"
echo "wp: 5050"
echo "php: 5000"
echo "grafana: 3000"
echo ""
echo "---> ssh admin@$(minikube ip) -p 4000 "
#to connect to nginx wirth ssh: ssh admin@$(minikube ip) -p 4000
#ftp $(minikube ip)
