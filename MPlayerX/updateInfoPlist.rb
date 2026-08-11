#!/usr/bin/env ruby
#
# Stamp the build number and the current commit hash into a built Info.plist.
#
# This used to edit the plist through RubyCocoa ("require 'osx/cocoa'"), which
# has not shipped with macOS since 10.9. plutil is used instead: it is part of
# the base system and needs no gems.

plist = ARGV[0]

if plist.nil? || plist.empty? || !File.exist?(plist)
  warn "usage: #{$PROGRAM_NAME} /path/to/Info.plist"
  exit 1
end

version = `bash version.sh`.chomp

if version.empty? || version == "unknown"
  # Happens in a shallow clone or an archive export, where the commit count
  # that version.sh derives the build number from is not available. Leave
  # whatever is already in the plist rather than writing a bogus value.
  warn "#{$PROGRAM_NAME}: version is not available from git; leaving Info.plist unchanged"
  exit 0
end

commit = `git rev-list --max-count=1 HEAD`.chomp

def plutil_set(plist, key, value)
  system("/usr/bin/plutil", "-replace", key, "-string", value, plist) ||
    system("/usr/bin/plutil", "-insert", key, "-string", value, plist) ||
    warn("failed to set #{key} in #{plist}")
end

plutil_set(plist, "CFBundleVersion", version)
plutil_set(plist, "MPXCommitHash", commit) unless commit.empty?

puts "version is valid: #{version}"
