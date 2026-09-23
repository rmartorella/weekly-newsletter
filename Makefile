IMAGE ?= ct-signal:dev
PORT  ?= 8088
NAME  ?= ct-signal-dev

.PHONY: build run up down logs headers csp validate lint test clean

build:
	docker build -t $(IMAGE) .

run up: build
	-docker rm -f $(NAME) 2>/dev/null
	docker run -d --name $(NAME) \
	  -p $(PORT):8080 \
	  --read-only \
	  --tmpfs /tmp:rw,noexec,nosuid,size=8m \
	  --tmpfs /var/cache/nginx:rw,noexec,nosuid,size=16m \
	  --tmpfs /var/run:rw,noexec,nosuid,size=1m \
	  --cap-drop ALL \
	  --security-opt no-new-privileges \
	  --memory 128m --cpus 0.5 \
	  $(IMAGE)
	@echo "http://localhost:$(PORT)"

down:
	-docker rm -f $(NAME)

logs:
	docker logs -f $(NAME)

headers:
	@curl -sS -D - -o /dev/null http://localhost:$(PORT)/

csp:
	python3 scripts/gen_csp.py src /dev/stdout

validate:
	python3 scripts/manifest_check.py k8s catalant-signal

lint: build
	docker run --rm --entrypoint nginx $(IMAGE) -t

test: build
	bash scripts/serve_test.sh $(IMAGE) 8099

clean: down
	-docker rmi $(IMAGE)
