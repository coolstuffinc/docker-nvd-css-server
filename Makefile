RCON_PASSWORD="defaultpassword"
CSS_HOSTNAME='"[N.V.D] MIX SERVER 2020"'
CSS_PASSWORD=""
STEAM_TOKEN=""

CONTAINER_ID=$(shell docker inspect --format="{{.Id}}" css-server)

build:
	docker build -t zoidicabra/steam-css .

start:
	docker start css-server

stop:
	docker stop css-server

remove: stop
	docker rm css-server

copy-demos:
	docker exec $(CONTAINER_ID) bash -c "mkdir -p demos; cp /home/steam/css/cstrike/*.dem demos"
	docker cp $(CONTAINER_ID):/home/steam/demos .
	docker exec $(CONTAINER_ID) bash -c "rm -rf demos"

run:
	docker run -d -p 27015:27015 \
	              -p 27015:27015/udp \
	              -p 1200:1200 \
	              -p 27005:27005/udp \
	              -p 27020:27020/udp \
	              -p 26901:26901/udp \
				  -e RCON_PASSWORD=$(RCON_PASSWORD) \
				  -e CSS_HOSTNAME=$(CSS_HOSTNAME) \
				  -e CSS_PASSWORD=$(CSS_PASSWORD) \
				  -e STEAM_TOKEN=$(STEAM_TOKEN) \
	              --name css-server \
	              zoidicabra/steam-css
