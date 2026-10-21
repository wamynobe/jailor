APP_NAME := Jailor
BUILD_DIR := build

.PHONY: app run icon test clean

app:
	./scripts/build-app.sh

run: app
	open "$(BUILD_DIR)/$(APP_NAME).app"

icon:
	swift scripts/make-icon.swift Resources

test:
	swift test

clean:
	rm -rf .build "$(BUILD_DIR)"
