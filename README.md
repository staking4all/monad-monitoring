# Monad Monitoring

The purpose of this repo is to assist validators/inidividuals to monitor their own Monad node installation.  

In order to use this repo/guide you need to already have a Monad node running. Also docker must be installed as this monitoring stack makes use of docker.

Currently, the Monad validator sends data to the Monad team using OpenTelemetry, and this process should continue. However, there is no metrics endpoint available from the Monad validator node at this time. This monitoring repository enables you to intercept the OpenTelemetry data, create a metrics endpoint, and still forward the same information to the Monad team. The repository runs its own OpenTelemetry, receives metrics from your Monad node, generates a metrics endpoint, and forwards the data to the Monad team, while also providing a Grafana dashboard for monitoring.

You do not need to use the OpenTelemetry provided with Monad install if using this as it is bundled with the same components. 

## Install 

To make use of this repository and get monitoring running follow the below steps

Clone the repository
```
git clone https://github.com/staking4all/monad-monitoring.git
```

Check .env variables for Grafana, change as needed
```
cd monad-monitoring
nano .env
```

To run a Monad node you can either use a binary or docker. To cater for both types of Monad installations we have provided two docker files. `docker-compose-binary.yaml` for a binary based installtion, `docker-compose-docker.yaml` for a docker based installation. Start up the monitoring stack with the relevant file.

For a binary installation use
```
docker compose -f docker-compose-binary.yaml up -d

```

For a docker installation use
```
docker compose -f docker-compose-docker.yaml up -d

```

Four containers should start that includes
- OpenTelemetry
- Prometheus
- Grafana
- Node exporter

For docker based Monad installations you must edit Monad Validator nodes `docker-compose.yml` to forward OpenTelemetry traffic to your installation. We assume the Monad validator installation is in your home directory. Within docker-compose.yml replace `--otel-endpoint http://peach10.devcore4.com:4317`  with your local otel `--otel-endpoint http://monad-monitoring-otel-collector-1:4317`. 
```
cd /home/monad/
nano docker-compose.yml
```

Restart your Monad validator if using docker based version
```
cd /home/monad/
docker compose down
docker compose up -d
```

If everything is working correctly you should be able to retrieve metrics on `http://localhost:8889/metrics`
```
curl http://localhost:8889/metrics
```

Open the required ports on your firewall as needed, for example to be able to view the Grafana dashbaord you will need to open port 3000. 
```
sudo ufw allow 3000/tcp
```

You will be able to access a grafana dashboard on `http://<your_own_ip_address>:3000` 

![image](https://github.com/user-attachments/assets/4f22bea3-4752-4fad-8c43-c2f0aee4bc0c)


The default dashboard is `Monad monitoring`, an additional dashboard has been added that is `Monad monitoring v2`. v2 adds some extra metrics however needs some extra config.

To use V2 you must make an entry in crontab by adding one of the below line, this script collects extra info to be displayed on the dashbaord

For Monad binary installation
````
* * * * * /home/monad/monad-monitoring/textfile-collector/script-data-collector-binary.sh >> /home/monad/error.log
````

For Monad docker installation
````
* * * * * /home/monad/monad-monitoring/textfile-collector/script-data-collector-docker.sh >> /home/monad/error.log
````

If using a binary installation you need to ensure the user monad for crontab can read the syslog files. 
````
sudo usermod -a -G adm monad
````

v2 adds the following metrics
- monad specific stats like round, epoch, etc
- triedb usage stats
- monad folders that should be cleared and monitored occasionally
- additional disk metrics

  

