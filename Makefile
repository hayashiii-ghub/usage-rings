.PHONY: build check run install
build:
	./script/build.sh
check:
	./script/check.sh
run: build
	open "dist/Usage Rings.app"
install:
	./script/install.sh
