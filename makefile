all: install

install:
	mkdir -p /usr/local/bin
	install -m 544 ifmon.sh /usr/local/bin/
