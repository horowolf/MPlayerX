#!/usr/bin/env ruby
#
# Print the CFBundleShortVersionString of a built .app to stdout.
#
# This used to read the plist through RubyCocoa ("require 'osx/cocoa'"), which
# has not shipped with macOS since 10.9, so the script raised a LoadError and
# the Localizations build phase then cd'd into a directory named after an empty
# version string. Read the value with plutil instead, which is part of the base
# system and needs no gems.

app = ARGV[0]

if app.nil? || app.empty?
  warn "usage: #{$PROGRAM_NAME} /path/to/Something.app"
  exit 1
end

plist = File.join(app, "Contents", "Info.plist")

unless File.exist?(plist)
  warn "#{$PROGRAM_NAME}: no Info.plist at #{plist}"
  exit 1
end

version = `/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "#{plist}"`.strip

if !$?.success? || version.empty?
  warn "#{$PROGRAM_NAME}: could not read CFBundleShortVersionString from #{plist}"
  exit 1
end

$stdout << version
