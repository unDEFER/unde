BIN     = $(DESTDIR)/usr/bin
SHARE   = $(DESTDIR)/usr/share/unde

all: unde

dub.json: dub.json_pre
	grep -q 14.04 /etc/lsb-release && sed 's/2.0.0/1.9.6/' dub.json_pre > dub.json || cp dub.json_pre dub.json

unde: dub.json
	OPTIONS="";\
	file /bin/bash | grep -q x86-64 || OPTIONS="--compiler=gdc";\
	grep -q 14.04 /etc/lsb-release && OPTIONS="$$OPTIONS -c Ubuntu_14_04";\
	dub build $$OPTIONS

install:
	install -d $(BIN)
	install unde $(BIN)/unde
	install -d $(SHARE)/layouts 
	for file in $$(find layouts -type f -name "*"); do \
		install -m 644 -D $$file $(SHARE)/$$file; \
	done
	install -d $(SHARE)/images
	for i in $$(find images -type f -name "*"); do \
		install $$i $(SHARE)/$$i; \
	done
