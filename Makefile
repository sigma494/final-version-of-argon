PY ?= .venv/bin/python
PIP ?= .venv/bin/pip
PORT ?= 8420
DEMO_PASSWORD ?= argon-demo-password
DEMO_VAULT ?= ./demo-vault.json

.PHONY: help venv install test lint demo serve clean

help:
	@echo "make install   - create .venv and install Argon (editable) + dev deps"
	@echo "make test      - run the pytest suite"
	@echo "make demo      - build a throwaway demo vault with sample entries"
	@echo "make serve     - run the web UI against the demo vault"
	@echo "make clean     - remove caches and the demo vault"

venv:
	python3 -m venv .venv

install: venv
	$(PIP) install -e ".[dev]"

test:
	$(PY) -m pytest -q

lint:
	$(PY) -m compileall -q argon

demo:
	ARGON_VAULT=$(DEMO_VAULT) ARGON_MASTER_PASSWORD='$(DEMO_PASSWORD)' $(PY) -m argon init --force
	ARGON_VAULT=$(DEMO_VAULT) ARGON_MASTER_PASSWORD='$(DEMO_PASSWORD)' $(PY) -m argon add GitHub -u octocat -g 28 --tags dev,work --url https://github.com
	ARGON_VAULT=$(DEMO_VAULT) ARGON_MASTER_PASSWORD='$(DEMO_PASSWORD)' $(PY) -m argon add ProtonMail -u you@example.com -g 24 --tags mail,personal --url https://mail.proton.me
	ARGON_VAULT=$(DEMO_VAULT) ARGON_MASTER_PASSWORD='$(DEMO_PASSWORD)' $(PY) -m argon add Router -u admin -p 'not-a-real-password' --notes 'LAN only. Reset wipes config.' --url 192.168.1.1 --tags infra
	ARGON_VAULT=$(DEMO_VAULT) ARGON_MASTER_PASSWORD='$(DEMO_PASSWORD)' $(PY) -m argon add Cloudflare --totp JBSWY3DPEHPK3PXP --no-password --tags infra,2fa
	@echo
	@echo "demo vault: $(DEMO_VAULT)  master password: $(DEMO_PASSWORD)"
	@echo "run: make serve"

serve:
	ARGON_VAULT=$(DEMO_VAULT) $(PY) -m argon serve --port $(PORT) --open

clean:
	rm -rf .pytest_cache .mypy_cache .ruff_cache **/__pycache__ $(DEMO_VAULT) $(DEMO_VAULT).bak
