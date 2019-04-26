REPO=blacktop/docker-zeek
ORG=blacktop
NAME=zeek
BUILD ?=$(shell cat LATEST)
LATEST ?=$(shell cat LATEST)


all: build size test

build: ## Build docker image
	cd $(BUILD); docker build -t $(ORG)/$(NAME):$(BUILD) .

.PHONY: size
size: build ## Get built image size
ifeq "$(BUILD)" "$(LATEST)"
	sed -i.bu 's/docker%20image-.*-blue/docker%20image-$(shell docker images --format "{{.Size}}" $(ORG)/$(NAME):$(BUILD)| cut -d' ' -f1)-blue/' README.md
	sed -i.bu '/latest/ s/[0-9.]\{3,5\}MB/$(shell docker images --format "{{.Size}}" $(ORG)/$(NAME):$(BUILD))/' README.md
endif
	sed -i.bu '/$(BUILD)/ s/[0-9.]\{3,5\}MB/$(shell docker images --format "{{.Size}}" $(ORG)/$(NAME):$(BUILD))/' README.md

.PHONY: tags
tags:
	docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" $(ORG)/$(NAME)

test: ## Test docker image
ifeq ($(BUILD),elastic)
	# @docker-compose -f docker-compose.elastic.yml up -d kibana
	# @docker-compose -f docker-compose.elastic.yml up bro
	# @http localhost:9200/_cat/indices
	# @open -a Safari https://goo.gl/e5v7Qr
	@docker run --rm $(ORG)/$(NAME):$(BUILD) --version
	@docker run --rm -v `pwd`/pcap:/pcap $(ORG)/$(NAME):$(BUILD) -r heartbleed.pcap local "Site::local_nets += { 192.168.11.0/24 }"
	@cat pcap/json_streaming_notice.1.log | jq .note
else ifeq ($(BUILD),kafka)
	@tests/kafka.sh
else ifeq ($(BUILD),redis)
	@docker-compose -f docker-compose.redis.yml up -d logstash
	@docker-compose -f docker-compose.elastic.yml up bro
	@http localhost:9200/_cat/indices
	@open -a Safari https://goo.gl/e5v7Qr
else
	@docker run --rm $(ORG)/$(NAME):$(BUILD) --version
	@docker run --rm -v `pwd`/pcap:/pcap -v `pwd`/scripts/local.bro:/usr/local/bro/share/bro/site/local.bro $(ORG)/$(NAME):$(BUILD) -r heartbleed.pcap local "Site::local_nets += { 192.168.11.0/24 }"
	@cat pcap/notice.log | awk '{ print $$11 }' | tail -n4
endif

.PHONY: tar
tar: ## Export tar of docker image
	docker save $(ORG)/$(NAME):$(BUILD) -o $(NAME).tar

.PHONY: push
push: build ## Push docker image to docker registry
	@echo "===> Pushing $(ORG)/$(NAME):$(BUILD) to docker hub..."
	@docker push $(ORG)/$(NAME):$(BUILD)

.PHONY: run
run: stop ## Run docker container
	@docker run --init -d --name $(NAME) -p 9200:9200 $(ORG)/$(NAME):$(BUILD)

.PHONY: start_elasticsearch
start_elasticsearch:
ifeq ("$(shell docker inspect -f {{.State.Running}} elasticsearch)", "true")
	@echo "===> elasticsearch already running.  Stopping now..."
	@docker rm -f elasticsearch || true
endif
	@echo "===> Starting elasticsearch"
	@docker run --init -d --name elasticsearch -p 9200:9200 malice/elasticsearch:7.0
	@wait-for-es

.PHONY: start_kibana
start_kibana:
ifeq ("$(shell docker inspect -f {{.State.Running}} kibana)", "true")
	@echo "===> kibana already running.  Stopping now..."
	@docker rm -f kibana || true
endif
	@echo "===> Starting kibana"
	@docker run --init -d --name kibana --link elasticsearch -p 5601:5601 blacktop/kibana:7.0

.PHONY: ssh
ssh: ## SSH into docker image
ifeq ($(BUILD),elastic)
ssh: start_elasticsearch start_kibana
	@docker run --init -it --rm --link elasticsearch --link kibana -v `pwd`/pcap:/pcap --entrypoint=sh $(ORG)/$(NAME):$(BUILD)
else
	@docker run --rm -v `pwd`/pcap:/pcap --entrypoint=sh $(ORG)/$(NAME):$(BUILD)
endif

.PHONY: stop
stop: ## Kill running docker containers
	@docker rm -f $(NAME) || true

.PHONY: stop-all
stop-all: ## Kill ALL running docker containers
	@docker-clean stop

.PHONY: circle
circle: ci-size ## Get docker image size from CircleCI
	@sed -i.bu 's/docker%20image-.*-blue/docker%20image-$(shell cat .circleci/SIZE)-blue/' README.md
	@echo "===> Image size is: $(shell cat .circleci/SIZE)"

ci-build:
	@echo "===> Getting CircleCI build number"
	@http https://circleci.com/api/v1.1/project/github/${REPO} | jq '.[0].build_num' > .circleci/build_num

ci-size: ci-build
	@echo "===> Getting image build size from CircleCI"
	@http "$(shell http https://circleci.com/api/v1.1/project/github/${REPO}/$(shell cat .circleci/build_num)/artifacts circle-token==${CIRCLE_TOKEN} | jq '.[].url')" > .circleci/SIZE

clean: ## Clean docker image and stop all running containers
	docker-clean stop
	docker rmi $(ORG)/$(NAME):$(BUILD) || true

# Absolutely awesome: http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
