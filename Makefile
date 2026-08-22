SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# Local commands. Apple targets need macOS + Xcode; Android needs the Android
# SDK but not a preinstalled JDK. Full map: Documentation/Repository.md

.PHONY: help doctor bootstrap format test coverage verify hooks \
	ios-run ios-build ios-boot ipados-run ipados-build watch-run watch-build \
	mac-run mac-build apple-devices \
	android-build android-release android-install android-run android-devices \
	android-test android-lint android-tasks android-clean gradle \
	docker-up docker-down docker-shell verify-devcontainer

help: ## Show available project commands
	@awk 'BEGIN {FS = ":.*## "; printf "Diffuse commands\n\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

doctor: ## Report which parts of Diffuse this machine can build
	./Scripts/doctor.sh

bootstrap: ## Install tools, generate the Xcode project, resolve packages
	./Scripts/bootstrap.sh

format: ## Apply SwiftFormat
	./Scripts/format.sh

test: ## Run the Swift package tests
	swift test --parallel

coverage: ## Swift package tests with a coverage report
	./Scripts/coverage.sh

verify: ## Format, tests, cross-checks, and unsigned builds of all Apple apps
	./Scripts/verify.sh

hooks: ## Install the Husky git hooks
	npm install

# ------------------------------------------------------------------ Apple ---

ios-run: ## Build, install, and launch DiffuseiOS on an iPhone simulator
	./Scripts/apple.sh run ios

ios-build: ## Build DiffuseiOS for an iPhone simulator
	./Scripts/apple.sh build ios

ios-boot: ## Boot an iPhone simulator and open Simulator.app
	./Scripts/apple.sh boot ios

ipados-run: ## Build, install, and launch DiffuseiPadOS on an iPad simulator
	./Scripts/apple.sh run ipados

ipados-build: ## Build DiffuseiPadOS for an iPad simulator
	./Scripts/apple.sh build ipados

watch-run: ## Build, install, and launch DiffuseWatch on a watch simulator
	./Scripts/apple.sh run watch

watch-build: ## Build DiffuseWatch for a watch simulator
	./Scripts/apple.sh build watch

mac-run: ## Build and launch DiffuseMac on this machine
	./Scripts/apple.sh run mac

mac-build: ## Build DiffuseMac
	./Scripts/apple.sh build mac

apple-devices: ## List available Apple simulators
	./Scripts/apple.sh devices ios

# ---------------------------------------------------------------- Android ---

android-run: ## Install and launch the Android app on a device or emulator
	./Scripts/android.sh run

android-build: ## Build the Android debug APK
	./Scripts/android.sh assembleDebug

android-release: ## Build the unsigned Android release APK
	./Scripts/android.sh assembleRelease

android-install: ## Build and install the debug APK on a connected device
	./Scripts/android.sh installDebug

android-test: ## Run Android unit tests with a coverage report
	./Scripts/android.sh jacocoDebugUnitTestReport

android-lint: ## Run Android lint
	./Scripts/android.sh lintDebug

android-devices: ## List connected Android devices and emulators
	./Scripts/android.sh devices

android-tasks: ## List every available Gradle task
	./Scripts/android.sh tasks

android-clean: ## Remove Android build output
	./Scripts/android.sh clean

gradle: ## Run any Gradle task, e.g. make gradle ARGS="assembleRelease"
	@test -n "$(ARGS)" || { printf 'Usage: make gradle ARGS="<gradle-task>"\n' >&2; exit 2; }
	./Scripts/android.sh $(ARGS)

# ----------------------------------------------------------------- Docker ---

docker-up: ## Start the containerised toolbox
	docker compose up -d --build

docker-down: ## Stop the containerised toolbox
	docker compose down

docker-shell: ## Open a shell in the containerised toolbox
	docker compose exec dev bash

verify-devcontainer: ## Build the toolbox image and verify its toolchain
	./Scripts/verify-devcontainer.sh
