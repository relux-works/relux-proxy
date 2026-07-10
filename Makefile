.PHONY: test build app dmg run clean

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
