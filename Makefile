.PHONY: lint test build app dmg run clean

lint:
	swift format lint --recursive --strict Sources Tests

test:
	swift test

build:
	swift build

app:
	scripts/build-app.sh

dmg: app
	scripts/create-dmg.sh

run: app
	open dist/ReluxProxy.app

clean:
	rm -rf .build dist
