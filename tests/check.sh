#!/bin/sh
# Template from the wow-addon-dev skill: unit tests, then static analysis (0 warnings
# required). Works from any directory. Rename FishDex to the addon folder.
set -e
cd "$(dirname "$0")/.."
luajit tests/run.lua
luacheck FishDex tests --config .luacheckrc
