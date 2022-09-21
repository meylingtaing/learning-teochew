test:
	carton exec -- prove -lr t

sandbox:
	carton exec -- morbo bin/webapp.pl

connect-db:
	sqlite3 Teochew.sqlite -column -header

setup-db:
	sqlite3 Teochew.sqlite < sql/setup_teochew.sql
	sqlite3 Updates.sqlite < sql/setup_updates.sql
