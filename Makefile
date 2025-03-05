test: setup-db
	carton exec -- prove -lr t

clean-teochew-db:
	sqlite3 Teochew.sqlite.tmp < sql/setup_teochew.sql
	mv Teochew.sqlite.tmp Teochew.sqlite

sandbox: setup-db
	carton exec -- morbo bin/webapp.pl

prod: clean-teochew-db Updates.sqlite
	carton install
	carton exec -- hypnotoad bin/webapp.pl

stop-prod:
	kill -3 `cat bin/hypnotoad.pid`

connect-db: Teochew.sqlite
	sqlite3 Teochew.sqlite -column -header

setup-db: Teochew.sqlite Updates.sqlite

Teochew.sqlite:
	sqlite3 Teochew.sqlite < sql/setup_teochew.sql

Updates.sqlite:
	sqlite3 Updates.sqlite < sql/setup_updates.sql

db-dump:
	sqlite3 Teochew.sqlite .dump > sql/setup_teochew.sql
	sqlite3 Updates.sqlite .dump > sql/setup_updates.sql
