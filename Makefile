SHELL := /bin/sh
PREFIX ?= $(HOME)/.local

.PHONY: help lint test test-all test-linux coverage check install

help:
	@echo "targets:"
	@echo "  lint        shellcheck -o all at zero findings"
	@echo "  test        bats suites under the system sh"
	@echo "  test-all    bats suites under every installed shell"
	@echo "  test-linux  the same suites in a privileged Ubuntu container"
	@echo "  coverage    kcov line coverage in the Ubuntu container, floor 66%"
	@echo "  check       lint and test"
	@echo "  install     copy bin/ and lib/ under PREFIX (default ~/.local)"

lint:
	shellcheck -x -s sh -o all bin/kakikomi bin/kiyome lib/*.sh scripts/*.sh
	shellcheck -x -o all test/*.sh test/*.bash test/*.bats test/shim/sudo

test:
	DISK_SHELLS=sh sh test/run-matrix.sh test

test-all:
	sh test/run-matrix.sh test

test-linux:
	sh test/linux-container.sh sh test/run-matrix.sh test

coverage:
	sh test/linux-container.sh sh -c 'apt-get install -y -qq kcov >/dev/null && sh scripts/coverage.sh 66'

check: lint test

install:
	mkdir -p "$(PREFIX)/share/kakikomi" "$(PREFIX)/bin"
	cp -R bin lib "$(PREFIX)/share/kakikomi/"
	printf '#!/bin/sh\nexec "%s/share/kakikomi/bin/kakikomi" "$$@"\n' "$(PREFIX)" > "$(PREFIX)/bin/kakikomi"
	printf '#!/bin/sh\nexec "%s/share/kakikomi/bin/kiyome" "$$@"\n' "$(PREFIX)" > "$(PREFIX)/bin/kiyome"
	chmod 755 "$(PREFIX)/bin/kakikomi" "$(PREFIX)/bin/kiyome"
