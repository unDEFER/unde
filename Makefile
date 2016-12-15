BIN     = $(DESTDIR)/usr/bin

all: unde

unde: dub.json
	dub build

install: all
	install unde $(BIN)/unde
