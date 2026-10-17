#!/bin/sh
# Build phase of the iOS app and the Watch app: writes the build information into the built Info.plist (and into the
# Info.plist of the app extensions embedded in it, i.e. the complication, which has no build phase of its own).
#   CFBundleVersion (the build number) = the number of commits in the history, so every commit has its own, rising number
#   and the number of an upload is read off the archived commit - nothing is bumped by hand (see docs/release.md).
#   GitCommitHash = the short hash, shown in Settings > About.
# Without a git history (e.g. a source archive) the build number stays as set in the project.
set -u
COUNT=$(git -C "${SRCROOT}" rev-list --count HEAD 2> /dev/null || echo "")
HASH=$(git -C "${SRCROOT}" rev-parse --short HEAD 2> /dev/null || echo "unknown")

stamp() { # Info.plist
  [ -f "$1" ] || return 0
  /usr/libexec/PlistBuddy -c "Delete :GitCommitHash" "$1" 2> /dev/null
  /usr/libexec/PlistBuddy -c "Add :GitCommitHash string ${HASH}" "$1"
  if [ -n "${COUNT}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${COUNT}" "$1"
  fi
}

stamp "${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
for extension in "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/PlugIns/"*.appex; do
  stamp "${extension}/Info.plist"
done
