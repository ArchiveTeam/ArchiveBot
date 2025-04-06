# ArchiveBot Viewer 2

This is the second version of the viewer. It was rewritten to make it perform better under a small VPS.

The viewer is a standalone system that fetches and indexes archive metadata from Internet Archive, and provides a web interface to browse and search them.

## Usage

Requires Rust to be installed.

Then run:

```sh
cargo build --release
```

The program will be built in the "target/release" directory.

By default, running the program will bring up a web server at http://localhost:8056/ and begin downloading archive metadata.

Run to see all options:

```sh
./archivebot-viewer --help
```
