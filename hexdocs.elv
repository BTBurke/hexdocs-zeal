#! /usr/bin/env elvish

use os
use path
use file

# get release information
fn get_latest_release {|ctx|
    try {
        curl -sL https://hex.pm/api/packages/$ctx[pkg] | var release = (from-json)[releases][0]
        set ctx = (assoc $ctx release $release)
     } catch e {
        nop
    } finally {
        put $ctx
    }
}

# download docs from hexdocs
fn download_docs {|ctx|
    var dir = (os:temp-dir "hexdocs")
    var file = $dir/$ctx[pkg]'-'$ctx[release][version].tar.gz
    curl --max-time 30 --retry 2 -Ls -o $file $ctx[release][url]/docs
    var ctx = (assoc $ctx base $dir)
    put (assoc $ctx tgz_file $file)
}

# extracts the downloaded docs
fn extract {|ctx|
    var dir = $ctx[base]
    var out_dir = $dir/$ctx[pkg]'.docset/Contents/Resources/Documents/'
    os:mkdir-all $out_dir

    tar -C $out_dir -xzf $ctx[tgz_file] --no-same-permissions --no-same-owner
    for f [$out_dir/*] {
        os:chmod 0o666 $f
    }
    os:remove $ctx[tgz_file]
    set ctx = (dissoc $ctx tgz_file)
    put (assoc $ctx docs $out_dir)
}

# builds the search index by populating a sqlite database with modules, types, constructors, and functions
fn build_search_index {|ctx|
    var p = (file:open-output $ctx[base]/docSet.sql)
    # create database
    echo "CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);" > $p
    echo "CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);" >> $p

    # extract from package interface relevant modules, types, constructors, functions
    jq '.modules | keys' $ctx[docs]/package-interface.json | var modules = (from-json)
    for module $modules {
        var mod_html = $module'.html'
        echo "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('"$module"', 'Module', '"$mod_html"');" >> $p
        jq '.modules["'$module'"] | .types | keys' $ctx[docs]/package-interface.json | var types = (from-json)
        for type $types {
            echo "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('"$type"', 'Type', '"$mod_html"#"$type"');" >> $p
            jq '.modules["'$module'"] | .types["'$type'"] | [.constructors[].name]' $ctx[docs]/package-interface.json | var constructors = (from-json)
            for constructor $constructors {
                echo "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('"$constructor"', 'Constructor', '"$mod_html"#"$type"');" >> $p
            }
        }
        jq '.modules["'$module'"] | .functions | keys' $ctx[docs]/package-interface.json | var functions = (from-json)
        for func $functions {
            echo "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('"$func"', 'Function', '"$mod_html"#"$func"');" >> $p
        }
    }
    file:close $p
    sqlite3 $ctx[base]/$ctx[pkg].docset/Contents/Resources/docSet.dsidx < $ctx[base]/docSet.sql
    os:remove $ctx[base]/docSet.sql
}

# adds the required apple plist file, enables js, adds JSON info about package version used by update/remove
fn make_plist {|ctx|
    var p = (file:open-output $ctx[base]/$ctx[pkg].docset/Contents/Info.plist)
    echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>'$ctx[pkg]'</string>
	<key>CFBundleName</key>
	<string>'$ctx[pkg]'</string>
	<key>DocSetPlatformFamily</key>
	<string>'$ctx[pkg]'</string>
	<key>isDashDocset</key>
	<true/>
    <key>DashDocSetFallbackURL</key>
    <string>https://hexdocs.pm/'$ctx[pkg]'</string>
    <key>isJavaScriptEnabled</key><true/>
</dict>
</plist>' > $p
    file:close $p

    #write a marker file with release details
    var p = (file:open-output $ctx[base]/$ctx[pkg].docset/hexdocs.json)
    var info = (put [&pkg=$ctx[pkg] &release=$ctx[release]] | to-json)
    echo $info > $p
    file:close $p
}

# fixes issues with file permissions that can happen after docs are extracted from tar file
fn fix_permissions {|ctx|
    var uid = (whoami)
    for d [$ctx[base]/**[type:dir]] {
        chown $uid':'$uid $d
        os:chmod 0o766 $d
        for f [$d/**/*[nomatch-ok][type:regular]] {
            chown $uid':'$uid $f
            os:chmod 0o666 $f
        }
    }
}

# moves the Zeal directory layout from the temp directory to zeal data directory
fn install_docset {|ctx|
    var install_path = ~/.local/share/Zeal/Zeal/docsets
    rm -rf $install_path/$ctx[pkg].docset
    mv $ctx[base]/$ctx[pkg].docset $install_path
}

fn do_install {|ctx|
    var previous_version = ""
    if (has-key $ctx release) {
        set previous_version = $ctx[release][version]
    }
    var ctx = (get_latest_release $ctx)
    if (not (has-key $ctx release)) {
        echo "No package found with name" $ctx[pkg] "or hex is down"
        exit 1
    }
    if (!=s $ctx[release][version] $previous_version) {
        var ctx = (download_docs $ctx)
        var ctx = (extract $ctx)
        build_search_index $ctx
        make_plist $ctx
        fix_permissions $ctx
        install_docset $ctx
        echo "Successfully installed" $ctx[pkg] "at version" $ctx[release][version]
    } else {
        echo "Package" $ctx[pkg] "is already at the latest version" $ctx[release][version]
    }
}

fn do_update {
    var install_path = ~/.local/share/Zeal/Zeal/docsets
    for d [$install_path/*[type:dir]] {
        if (os:exists $d/hexdocs.json) {
            cat $d/hexdocs.json | var info = (from-json)
            do_install $info
        }
    }
}

fn do_remove {|ctx|
    var install_path = ~/.local/share/Zeal/Zeal/docsets
    var removed = []
    for d [$install_path/*[type:dir][nomatch-ok]] {
        if (os:exists $d/hexdocs.json) {
            cat $d/hexdocs.json | var info = (from-json)
            if (or $ctx[all] (==s $ctx[pkg] $info[pkg])) {
                set removed = (conj $removed $info[pkg])
                rm -rf $d
            }
       }
    }
    put [&pkgs=$removed]
}

var help = "
Usage: hexdocs <command>

Commands:
    add <package>   Installs docs for package
    update              Update all
    remove <package>    Remove package docs
    remove all          Remove all hexdocs
"

# add a package
if (==s $args[0] "add") {
    if (or (< (count $args) 2) (==s $args[1] "")) {
        echo $help
        exit 1
    } else {
        do_install [&pkg=$args[1]]
        exit 0
    }
}

# update all packages
if (==s $args[0] "update") {
    do_update
    exit 0
}

# remove a single or all packages
if (==s $args[0] "remove") {
    if (or (< (count $args) 2) (==s $args[1] "")) {
        echo $help
        exit 1
    }
    var removed = [&pkgs=[]]
    if (==s $args[1] "all") {
        set removed = (do_remove [&all=$true])
    } else {
        set removed = (do_remove [&pkg=$args[1] &all=$false])
    }
    if (> (count $removed[pkgs]) 0) {
        for pkg $removed[pkgs] {
            echo "Removed" $pkg
        }
    } else {
        echo "No package(s) found"
    }
    exit 0
}

echo $help
exit 1

