BIN     = $(DESTDIR)/usr/bin
SHARE   = $(DESTDIR)/usr/share/unde

all: unde

unde: dub.json
	file /bin/bash | grep -q x86-64 && dub build || dub build --compiler=gdc

install: all
	install unde $(BIN)/unde
	install -d $(SHARE)/layouts 
	for file in $$(find layouts -type f -name "*"); do \
		install -m 644 -D $$file $(SHARE)/$$file; \
	done
	install -d $(SHARE)/images
	for i in $$(find images -type f -name "*"); do \
		install $$i $(SHARE)/$$i; \
	done
