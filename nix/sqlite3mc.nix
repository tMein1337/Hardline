# SPDX-FileCopyrightText: 2026 Mein1337
# SPDX-License-Identifier: AGPL-3.0-or-later

# SQLite3 Multiple Ciphers, built from source as a shared library.
#
# On every other platform package:sqlite3's build hook downloads this library
# prebuilt from GitHub (`hooks.user_defines.sqlite3.source: sqlite3mc` in
# pubspec.yaml). The Nix sandbox has no network, so flake.nix points the hook
# at this derivation instead (`source: system` with an absolute `name`).
#
# Same library, same cipher, same on-disk format as the Windows and macOS
# builds: a store encrypted on one opens on the others. The version is the one
# package:sqlite3 bundles in the release pinned in pubspec.lock
# (sqlite3 3.5.1 -> SQLite3 Multiple Ciphers 2.5.0, SQLite 3.53.4; see the
# package's CHANGELOG). Re-pin both together when sqlite3 moves.
#
# The compile-time options are package:sqlite3's own (doc/hook.md, "Default
# binaries"), so the Dart bindings find what they expect.
{
  lib,
  stdenv,
  fetchFromGitHub,
}:

let
  defines = [
    "SQLITE_ENABLE_DBSTAT_VTAB"
    "SQLITE_ENABLE_FTS5"
    "SQLITE_ENABLE_RTREE"
    "SQLITE_ENABLE_MATH_FUNCTIONS"
    "SQLITE_DQS=0"
    "SQLITE_DEFAULT_MEMSTATUS=0"
    "SQLITE_TEMP_STORE=2"
    "SQLITE_MAX_EXPR_DEPTH=0"
    "SQLITE_STRICT_SUBTYPE=1"
    "SQLITE_OMIT_AUTHORIZATION"
    "SQLITE_OMIT_DECLTYPE"
    "SQLITE_OMIT_DEPRECATED"
    "SQLITE_OMIT_PROGRESS_CALLBACK"
    "SQLITE_OMIT_SHARED_CACHE"
    "SQLITE_OMIT_TCL_VARIABLE"
    "SQLITE_OMIT_TRACE"
    "SQLITE_USE_ALLOCA"
    "SQLITE_ENABLE_SESSION"
    "SQLITE_ENABLE_PREUPDATE_HOOK"
    "SQLITE_UNTESTABLE"
    "SQLITE_HAVE_ISNAN"
    "SQLITE_HAVE_LOCALTIME_R"
    "SQLITE_HAVE_MALLOC_USABLE_SIZE"
    "SQLITE_HAVE_STRCHRNUL"
    # SQLITE_HAVE_LOCALTIME_S from the list is Windows-only (localtime_s);
    # glibc has none, and defining it breaks the build there.
  ];
  cflags = lib.concatMapStringsSep " " (d: "-D${d}") defines;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "sqlite3mc";
  version = "2.5.0";

  src = fetchFromGitHub {
    owner = "utelle";
    repo = "SQLite3MultipleCiphers";
    tag = "v${finalAttrs.version}";
    hash = lib.fakeHash;
  };

  # src/sqlite3mc.c is the library's single compilation unit: it includes
  # SQLite itself and every cipher. Nothing else in the tree is needed.
  buildPhase = ''
    runHook preBuild
    $CC -O2 -fPIC -shared -o libsqlite3mc.so \
      ${cflags} \
      -Isrc src/sqlite3mc.c \
      -Wl,-soname,libsqlite3mc.so \
      -lm -lpthread -ldl
    runHook postBuild
  '';

  # Prove the one thing the app relies on: a key set through PRAGMA actually
  # encrypts, with the scheme store_cipher.dart pins (chacha20). Plain SQLite
  # would accept the same pragmas and write plaintext, which is the failure
  # this library exists to rule out.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    cat > check.c <<'EOF'
    #include <stdio.h>
    #include <string.h>
    #include "sqlite3.h"
    static int run(sqlite3 *db, const char *sql) {
      char *err = 0;
      if (sqlite3_exec(db, sql, 0, 0, &err) != SQLITE_OK) {
        fprintf(stderr, "%s: %s\n", sql, err ? err : "?");
        return 1;
      }
      return 0;
    }
    static int one(void *out, int n, char **v, char **c) {
      (void)n; (void)c; snprintf((char *)out, 64, "%s", v[0] ? v[0] : ""); return 0;
    }
    int main(void) {
      sqlite3 *db; char version[64] = ""; char head[16]; FILE *f;
      remove("t.db");
      if (sqlite3_open("t.db", &db)) return 1;
      if (sqlite3_exec(db, "SELECT sqlite3mc_version()", one, version, 0)) return 2;
      if (run(db, "PRAGMA cipher = 'chacha20'") || run(db, "PRAGMA key = 'k'")
          || run(db, "CREATE TABLE t(x); INSERT INTO t VALUES ('secret')")) return 3;
      sqlite3_close(db);
      f = fopen("t.db", "rb"); if (!f || fread(head, 1, 16, f) != 16) return 4; fclose(f);
      if (memcmp(head, "SQLite format 3", 15) == 0) { fprintf(stderr, "plaintext\n"); return 5; }
      if (sqlite3_open("t.db", &db)) return 6;
      if (sqlite3_exec(db, "SELECT count(*) FROM t", 0, 0, 0) == SQLITE_OK) {
        fprintf(stderr, "opened without the key\n"); return 7;
      }
      sqlite3_close(db);
      if (sqlite3_open("t.db", &db)) return 8;
      if (run(db, "PRAGMA cipher = 'chacha20'") || run(db, "PRAGMA key = 'k'")
          || run(db, "SELECT x FROM t")) return 9;
      sqlite3_close(db);
      printf("sqlite3mc %s encrypts\n", version);
      return 0;
    }
    EOF
    $CC -Isrc check.c -L. -lsqlite3mc -Wl,-rpath,"$PWD" -o check
    ./check
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 libsqlite3mc.so "$out/lib/libsqlite3mc.so"
    install -Dm644 src/sqlite3mc.h "$out/include/sqlite3mc.h"
    mkdir -p "$out/share/licenses/sqlite3mc"
    cp LICENSE* "$out/share/licenses/sqlite3mc/"
    runHook postInstall
  '';

  meta = {
    description = "SQLite3 Multiple Ciphers, the encrypting SQLite build package:sqlite3 uses";
    homepage = "https://github.com/utelle/SQLite3MultipleCiphers";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
