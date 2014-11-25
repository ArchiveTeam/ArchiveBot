ArchiveBot Viewer
=================

Standalone ArchiveBot archive viewer.

The viewer automatically fetches archive metadata information from Internet Archive and creates an local database. It allows simple browsing and searching.


Install
=======

Requires:

* Python 3.
* [Tornado](https://tornadoweb.org/)
* [dateutil](https://pypi.python.org/pypi/python-dateutil)

Quick start:

        python3 -m archivebotviewer

The command will bring up a web server at http://localhost:8056/ and begin downloading archive metadata.

To complement the dashboard behind a web server:

        python3 -m archivebotviewer --xheaders --prefix /viewer/ --data-dir /var/lib/archivebotviewer/data/

If you have problems with the database, try deleting and letting it repopulate.
