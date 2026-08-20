# Local commands. `verify` and `test` need macOS + Xcode.
# Full map: Documentation/Repository.md

.PHONY: bootstrap format test coverage verify docker-up docker-down docker-shell hooks

bootstrap:
	./Scripts/bootstrap.sh

format:
	./Scripts/format.sh

test:
	swift test --parallel

coverage:
	./Scripts/coverage.sh

verify:
	./Scripts/verify.sh

hooks:
	npm install

docker-up:
	docker compose up -d --build

docker-down:
	docker compose down

docker-shell:
	docker compose exec dev bash
