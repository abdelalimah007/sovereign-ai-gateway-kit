# Optional helpers. The three commands in the README are all you need.
.PHONY: up down test test-fallback verify clean logs

up:            ## start the stack (copies .env.example to .env if missing)
	@test -f .env || cp .env.example .env
	docker compose up -d

down:          ## stop the stack, keep the downloaded models
	docker compose down

test:          ## run the demo (cases A-G)
	./test-prompts.sh

test-fallback: ## run the demo including the fallback case H (stops tap briefly)
	./test-prompts.sh --with-fallback

verify:        ## acceptance checks (clean start: deletes and re-downloads the models)
	./scripts/verify.sh

logs:          ## follow the gateway's metadata log
	docker compose logs -f litellm

clean:         ## stop the stack and delete the model volume
	docker compose down -v
