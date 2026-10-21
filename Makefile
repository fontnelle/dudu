# Recipes need a POSIX shell: GNU make on Windows would otherwise use cmd.exe.
SHELL := bash
# No quotes in $(shell): GNU make on Windows hands them to the shell its own way.
VERSION := $(subst ",,$(subst VERSION=,,$(shell grep -m1 VERSION= dudu)))
SOURCES := dudu install.sh packaging/release-notes.sh $(wildcard lib/*/*.sh) $(wildcard bin/*.sh)

.PHONY: lint test check dist install clean

TESTS := $(wildcard tests/*.bats) tests/helpers.bash

lint:
	shellcheck $(SOURCES)
	@# Each bats test runs in its own subshell, so changing HOME or PATH there is intended.
	shellcheck -e SC2030,SC2031,SC2012,SC2155 $(TESTS)
	@# Under bash 3.2 a failing [[ ]] does not fail a bats test: end each one with || false.
	@! grep -nE '^[[:space:]]+\[\[ .*\]\][[:space:]]*$$' $(wildcard tests/*.bats) | grep .
	@if command -v zsh >/dev/null; then zsh -n completions/dudu.zsh completions/_dudu; fi
	@# Every message has a translation in each catalog, with the same %s/%d.
	bash tests/i18n_check.sh
	@# The version in dudu has its release notes in CHANGELOG.windows.md.
	@packaging/release-notes.sh --title $(VERSION) >/dev/null
	@# bash 3.2 reads "$VAR" followed by a UTF-8 byte as part of the name: write "${VAR}".
	@! perl -ne 'print "$$ARGV:$$.: $$_" if /\$$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/; close ARGV if eof' $(SOURCES) | grep .

test:
	bats tests/

check: lint test

# Release tarball + checksums, as install.sh expects them.
dist:
	mkdir -p dist
	git archive --format=tar.gz --prefix=dudu-$(VERSION)/ -o dist/dudu-$(VERSION).tar.gz HEAD
	cd dist && shasum -a 256 dudu-$(VERSION).tar.gz > SHA256SUMS

# Links this checkout as the dudu command (dudu update then uses git pull).
install:
	mkdir -p $(HOME)/.local/bin
	ln -sf $(CURDIR)/dudu $(HOME)/.local/bin/dudu

clean:
	rm -rf dist
