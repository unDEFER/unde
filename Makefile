BIN     = $(DESTDIR)/usr/bin

all: unde

unde: dub.json
	file /bin/bash | grep -q x86-64 && dub build || dub build --compiler=gdc

install: all
	install unde $(BIN)/unde
