# Tests use the shared bats-test image and the helper submodules in tests/helpers.
# `make help` lists the targets. DISTRO=fedora selects the glibc image.
SHELL := bash
.DEFAULT_GOAL := help

RUNTIME      ?= podman
BASH_VERSION ?= 5.2
BATS_VERSION ?= 1.14.0
DISTRO       ?= alpine
ifeq ($(DISTRO),fedora)
IMAGE        ?= ghcr.io/stealth-scale/bats-test:fedora
else
IMAGE        ?= ghcr.io/stealth-scale/bats-test:bash$(BASH_VERSION)-bats$(BATS_VERSION)
endif
# Never discover the helper libraries' own suites or the intentional failures.
SUITES        = $(shell find tests -name '*.bats' -not -path 'tests/helpers/*' | sort)
TARGET       ?= $(SUITES)
BATS_FLAGS   ?= --print-output-on-failure
COVERAGE_MIN ?= 100
SHELLCHECK   ?= shellcheck

SOURCES = bin/releasectl $(shell find src -name '*.bash' | sort) $(wildcard scripts/*.bash)
TESTS   = tests/helpers/example/load.bash $(SUITES) $(wildcard examples/*.bats)

# The image forwards signals to its children. Only coverage/ is mounted writable.
RUN = $(RUNTIME) run --rm --network=none --cap-drop=ALL --security-opt=label=disable \
      --user $(shell id -u):$(shell id -g) $(if $(filter podman,$(RUNTIME)),--userns=keep-id) \
      --env BATS_LIB_PATH=/code/tests/helpers \
      --volume "$(CURDIR):/code:ro" --workdir /code

.PHONY: help check-helpers test test-host test-reports coverage lint check shell clean

help: ## List the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{ printf "  %-14s %s\n", $$1, $$2 }'

check-helpers: ## Check that the helper submodules are initialized (no Git writes)
	@for helper in bats-expect bats-mock bats-matrix; do \
	  test -f "tests/helpers/$$helper/load.bash" || { \
	    printf 'Missing %s. Run: git submodule update --init --recursive\n' "$$helper" >&2; \
	    printf 'Initial checkout without gitlinks? Follow CONTRIBUTING.md: Initial repository bootstrap.\n' >&2; \
	    exit 1; \
	  }; \
	done

test: check-helpers ## Run TARGET in the shared image, without network access
	$(RUN) $(IMAGE) test $(BATS_FLAGS) --recursive $(TARGET)

test-host: check-helpers ## Run TARGET with this machine's Bash, bats and jq
	BATS_LIB_PATH="$(CURDIR)/tests/helpers" bats $(BATS_FLAGS) --recursive $(TARGET)

test-reports: check-helpers ## Verify that the three failure demos fail for the intended reasons
	bash scripts/check-reports.bash $(RUN) $(IMAGE) test --formatter tap examples/failures.bats

coverage: check-helpers ## Run TARGET under kcov; report in coverage/, floor COVERAGE_MIN%
	rm -rf coverage && mkdir coverage
	$(RUN) --volume "$(CURDIR)/coverage:/code/coverage" $(IMAGE) coverage --min $(COVERAGE_MIN) $(COVERAGE_FLAGS) -- $(BATS_FLAGS) --recursive $(TARGET)

lint: ## Check the application, harness and examples, not the helper submodules
	$(SHELLCHECK) -x $(SOURCES) $(TESTS)

check: lint test test-reports ## Run lint, the normal suite and the diagnostic checks

shell: check-helpers ## Open a shell in the shared image
	$(RUN) --interactive --tty $(IMAGE) shell

clean: ## Remove the generated coverage report
	rm -rf coverage
