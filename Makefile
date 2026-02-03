.PHONY: deploy clean status

deploy:
	@bash scripts/deploy.sh

status:
	@localstack status services || true

clean:
	@bash scripts/clean.sh || true
