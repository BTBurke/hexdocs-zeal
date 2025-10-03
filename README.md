# Hexdocs Zeal

This is a script to download Gleam package documentation to the [Zeal](https://zealdocs.org/) offline documentation browser.  Zeal is an open source version of the Mac app [Dash](https://kapeli.com/dash), but unlike Dash it doesn't have the ability to directly download docs from [hexdocs](https://hexdocs.pm/).

When learning gleam, I got tired of switching back and forth between multiple hexdocs tabs.  I wanted docs in Zeal where I can search and work offline.

![screenshot of zeal with hexdocs package docs](screenshot.png)

# Installation

This script is written in [Elvish](https://elv.sh/), a shell and scripting language based on functional programming and typed values. To run it, you will need:

* **jq**: to extract modules, types, constructors, and functions for the search index
* **elvish**: to run the script
* **tar**: to extract the docs
* **sqlite3**: to construct the Zeal search index
* **curl**: to download the docs

It will only work on unix-like systems due to the use of typical shell commands for copying and moving files.

Put [hexdocs.elv](https://github.com/BTBurke/hexdocs-zeal/blob/main/hexdocs.elv) somewhere on your path.  I symlink it to `/usr/local/bin/hexdocs`.

# Managing Package Documentation

```
# add package docs
hexdocs add <package>

# update all package docs
hexdocs update

# remove package docs
hexdocs remove <package>

# remove all hexdocs packages
hexdocs remove all
```

# FAQ

## Why use Elvish?

I wanted to experiment with Elvish scripting and its use of typed values.  This was a small project to learn the language and use it in anger.

## Will it work on Windows?

It should work in WSL.

## Why not use Zeal feeds?

Zeal has the ability to read docset data from an XML feed and update docsets automatically when new versions are released.  That would be a better way to do it, but I can't be bothered to set up a server just to host a few docsets I can download manually in the terminal.
