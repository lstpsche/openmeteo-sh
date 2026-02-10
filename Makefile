DESTDIR ?=
PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
LIBEXEC ?= $(PREFIX)/libexec/openmeteo
COMPDIR_BASH ?= $(PREFIX)/share/bash-completion/completions
COMPDIR_ZSH  ?= $(PREFIX)/share/zsh/site-functions

.PHONY: all install uninstall

all:
	@: # nothing to build — pure shell project

install:
	@echo "Installing openmeteo to $(DESTDIR)$(LIBEXEC) ..."
	install -d $(DESTDIR)$(LIBEXEC)/lib $(DESTDIR)$(LIBEXEC)/commands
	install -m 755 openmeteo         $(DESTDIR)$(LIBEXEC)/openmeteo
	install -m 644 lib/core.sh       $(DESTDIR)$(LIBEXEC)/lib/core.sh
	install -m 644 lib/output.sh     $(DESTDIR)$(LIBEXEC)/lib/output.sh
	install -m 644 lib/geo.sh        $(DESTDIR)$(LIBEXEC)/lib/geo.sh
	install -m 644 commands/weather.sh      $(DESTDIR)$(LIBEXEC)/commands/weather.sh
	install -m 644 commands/geo.sh          $(DESTDIR)$(LIBEXEC)/commands/geo.sh
	install -m 644 commands/history.sh      $(DESTDIR)$(LIBEXEC)/commands/history.sh
	install -m 644 commands/ensemble.sh     $(DESTDIR)$(LIBEXEC)/commands/ensemble.sh
	install -m 644 commands/climate.sh      $(DESTDIR)$(LIBEXEC)/commands/climate.sh
	install -m 644 commands/marine.sh       $(DESTDIR)$(LIBEXEC)/commands/marine.sh
	install -m 644 commands/air_quality.sh  $(DESTDIR)$(LIBEXEC)/commands/air_quality.sh
	install -m 644 commands/flood.sh        $(DESTDIR)$(LIBEXEC)/commands/flood.sh
	install -m 644 commands/elevation.sh    $(DESTDIR)$(LIBEXEC)/commands/elevation.sh
	install -m 644 commands/satellite.sh    $(DESTDIR)$(LIBEXEC)/commands/satellite.sh
	@echo "Symlinking $(DESTDIR)$(BINDIR)/openmeteo -> $(LIBEXEC)/openmeteo"
	install -d $(DESTDIR)$(BINDIR)
	ln -sf $(LIBEXEC)/openmeteo $(DESTDIR)$(BINDIR)/openmeteo
	@# Shell completions
	@if [ -f completions/openmeteo.bash ]; then \
		install -d $(DESTDIR)$(COMPDIR_BASH); \
		install -m 644 completions/openmeteo.bash $(DESTDIR)$(COMPDIR_BASH)/openmeteo; \
	fi
	@if [ -f completions/openmeteo.zsh ]; then \
		install -d $(DESTDIR)$(COMPDIR_ZSH); \
		install -m 644 completions/openmeteo.zsh $(DESTDIR)$(COMPDIR_ZSH)/_openmeteo; \
	fi
	@echo "Done. Run 'openmeteo --version' to verify."

uninstall:
	@echo "Removing openmeteo ..."
	rm -f  $(DESTDIR)$(BINDIR)/openmeteo
	rm -rf $(DESTDIR)$(LIBEXEC)
	rm -f  $(DESTDIR)$(COMPDIR_BASH)/openmeteo 2>/dev/null || true
	rm -f  $(DESTDIR)$(COMPDIR_ZSH)/_openmeteo 2>/dev/null || true
	@echo "Done."
