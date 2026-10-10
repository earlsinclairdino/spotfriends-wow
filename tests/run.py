"""Run SpotFriends' Lua tests through lupa's Lua 5.1 (`pip install lupa`), no luajit needed.

    python tests/run.py              # every tests/*_test.lua, and a syntax check of every addon file
    python tests/run.py resolver     # only the files whose name contains this
    python tests/run.py -v layout    # with each file's own output
"""
import glob
import locale
import os
import sys

# Python's Windows locale makes Lua's %s match byte 0xA0; the client runs in the C locale.
locale.setlocale(locale.LC_CTYPE, "C")

from lupa import lua51  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)


def lua_path(path):
    return path.replace("\\", "/")


def check_syntax():
    lua = lua51.LuaRuntime()
    failures = 0
    for path in sorted(glob.glob(os.path.join(ADDON, "*.lua"))):
        with open(path, "rb") as handle:
            source = handle.read()
        err = lua.eval("function(s, n) local f, e = loadstring(s, n); return f == nil and e or false end")(
            source, os.path.basename(path))
        if err:
            failures += 1
            print("SYNTAX  %s: %s" % (os.path.basename(path), err))
    return failures


def run(path, verbose):
    lua = lua51.LuaRuntime()
    lua.execute('ADDON_DIR = "%s/"' % lua_path(ADDON))
    lua.globals().arg = lua.table_from({0: lua_path(path)})
    output = []
    lua.globals().print = lambda *args: output.append(" ".join(str(a) for a in args))
    try:
        lua.execute('dofile("%s")' % lua_path(path))
        ok = True
    except Exception as err:  # a failed expectation raises a Lua error
        output.append(str(err))
        ok = False
    name = os.path.basename(path)
    print("%s  %s" % ("ok  " if ok else "FAIL", name))
    if verbose or not ok:
        for line in output:
            print("      " + line)
    return ok


def main():
    args = [a for a in sys.argv[1:] if a != "-v"]
    verbose = "-v" in sys.argv
    pattern = args[0] if args else ""
    failures = check_syntax()
    files = sorted(glob.glob(os.path.join(HERE, "*_test.lua")))
    files = [f for f in files if pattern in os.path.basename(f)]
    for path in files:
        if not run(path, verbose):
            failures += 1
    print("%d file(s), %d failure(s)" % (len(files), failures))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
