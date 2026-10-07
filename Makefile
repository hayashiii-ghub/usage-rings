.PHONY: build check run install package package-draft package-unnotarized
build:
	./script/build.sh
check:
	./script/check.sh
run: build
	open "dist/Usage Rings.app"
install:
	./script/install.sh
package:
	python3 ./script/package.py
package-draft:
	python3 ./script/package.py --draft
package-unnotarized:
	python3 ./script/package.py --unnotarized
