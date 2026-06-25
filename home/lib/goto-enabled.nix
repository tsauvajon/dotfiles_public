# Shared predicate for enabling goto's CLI config and local launchd API.
{ lib }:

{ apiUrl, bookmarksFile }:
lib.isString apiUrl && apiUrl != "" && bookmarksFile != null && toString bookmarksFile != ""
