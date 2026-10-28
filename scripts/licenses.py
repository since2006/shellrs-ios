#!/usr/bin/env python3
"""Writes ShellRS/About/Licenses.json: the open-source code the app ships
and the texts of its licenses, for 设置 › 开源许可.

  SHELLRS_DIR  the shell-rs checkout, ../shell-rs unless set

The Rust crates are those the core links on iOS, from shell-rs's Cargo
metadata: shellrs-mobile's normal dependencies, without proc-macros (they
run while compiling and ship nothing) and without shell-rs's own crates.
SwiftTerm's version comes from Package.resolved, its license from its
checkout under build/SourcePackages; without one, the entry already in
the file is kept. scripts/build-core.sh runs this after building the core.

A crate under a choice of licenses ("MIT OR Apache-2.0") is listed with the
text of the one taken, MIT first; one under several at once gets every
license file it has. A crate that ships no license file gets its license's
standard text from scripts/license-texts.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ShellRS", "About", "Licenses.json")
STANDARD = os.path.join(ROOT, "scripts", "license-texts")
SHELLRS = os.path.abspath(os.environ.get("SHELLRS_DIR", os.path.join(ROOT, "..", "shell-rs")))

# The license taken from a choice, the first that is offered.
PREFERRED = ["MIT", "Apache-2.0", "BSD-3-Clause", "BSD-2-Clause", "ISC", "Zlib",
             "Unicode-3.0", "MPL-2.0", "MIT-0", "0BSD", "BSL-1.0", "CC0-1.0", "Unlicense"]

LICENSE_FILE = re.compile(r"(?i)^(licen[cs]e|copying|unlicense)")
NOTICE_FILE = re.compile(r"(?i)^notice")

# Words that tell a license file's license.
SIGNS = [
    ("Apache-2.0", r"Apache License\s+Version 2\.0"),
    ("MPL-2.0", r"Mozilla Public License,? [Vv]ersion 2\.0"),
    ("Unicode-3.0", r"UNICODE LICENSE V3|Unicode, Inc\."),
    ("BSL-1.0", r"Boost Software License"),
    ("Unlicense", r"This is free and unencumbered software"),
    ("CC0-1.0", r"CC0 1\.0 Universal"),
    ("Zlib", r"This software is provided 'as-is', without any express or implied"),
    ("ISC", r"Permission to use, copy, modify, and(/or)? distribute this software for any"),
    ("BSD-3-Clause", r"Neither the name of"),
    ("BSD-2-Clause", r"Redistribution and use in source and binary forms"),
    ("MIT-0", r"Permission is hereby granted, free of charge(?![\s\S]*The above copyright notice)"),
    ("MIT", r"Permission is hereby granted, free of charge"),
]


def license_of(path, text):
    """The license a file holds, by its name or else its words."""
    name = os.path.basename(path).upper()
    for spdx, hint in [("MIT", "MIT"), ("Apache-2.0", "APACHE"), ("Zlib", "ZLIB"),
                       ("BSL-1.0", "BOOST"), ("Unlicense", "UNLICENSE")]:
        if hint in name:
            return spdx
    for spdx, pattern in SIGNS:
        if re.search(pattern, text):
            return spdx
    return None


def choices(expression):
    """The licenses a plain "A OR B" lets one choose from; None when the
    expression takes several at once."""
    expression = expression.replace("/", " OR ")
    if " AND " in expression or "(" in expression or " WITH " in expression:
        return None
    return [part.strip() for part in expression.split(" OR ")]


def read(path):
    with open(path, encoding="utf-8", errors="replace") as file:
        return file.read().strip() + "\n"


def standard(spdx):
    path = os.path.join(STANDARD, spdx + ".txt")
    if not os.path.exists(path):
        sys.exit(f"no license file and no standard text for {spdx}")
    return read(path)


def crate_texts(package):
    folder = os.path.dirname(package["manifest_path"])
    expression = package["license"] or ""
    files = sorted(
        os.path.join(folder, name) for name in os.listdir(folder)
        if LICENSE_FILE.match(name) and os.path.isfile(os.path.join(folder, name)))
    if package["license_file"]:
        files.append(os.path.join(folder, package["license_file"]))
    files = list(dict.fromkeys(files))
    notices = [read(os.path.join(folder, name)) for name in sorted(os.listdir(folder))
               if NOTICE_FILE.match(name) and os.path.isfile(os.path.join(folder, name))]
    found = [(license_of(path, read(path)), read(path)) for path in files]

    offered = choices(expression) if expression else None
    if offered:
        taken = next((spdx for spdx in PREFERRED if spdx in offered), offered[0])
        texts = [text for spdx, text in found if spdx == taken]
        if not texts:
            texts = [text for _, text in found] or [standard(taken)]
        return taken, texts + notices
    if not found:
        sys.exit(f"{package['name']} {package['version']}: no license file for {expression}")
    return expression, [text for _, text in found] + notices


def rust_packages():
    metadata = json.loads(subprocess.check_output(
        ["cargo", "metadata", "--format-version", "1", "--locked",
         "--filter-platform", "aarch64-apple-ios"],
        cwd=SHELLRS))
    packages = {package["id"]: package for package in metadata["packages"]}
    nodes = {node["id"]: node for node in metadata["resolve"]["nodes"]}
    own = set(metadata["workspace_members"])
    root = next(id for id, package in packages.items() if package["name"] == "shellrs-mobile")
    shipped, stack, seen = [], [root], set()
    while stack:
        id = stack.pop()
        if id in seen:
            continue
        seen.add(id)
        package = packages[id]
        if any("proc-macro" in target["kind"] for target in package["targets"]):
            continue
        if id not in own:
            shipped.append(package)
        for dependency in nodes[id]["deps"]:
            if any(kind["kind"] is None for kind in dependency["dep_kinds"]):
                stack.append(dependency["pkg"])
    return shipped


def swiftterm(previous):
    with open(os.path.join(ROOT, "ShellRS.xcodeproj", "project.xcworkspace", "xcshareddata",
                           "swiftpm", "Package.resolved")) as file:
        pin = next(pin for pin in json.load(file)["pins"] if pin["identity"] == "swiftterm")
    version = pin["state"]["version"]
    license_path = os.path.join(ROOT, "build", "SourcePackages", "checkouts", "SwiftTerm", "LICENSE")
    if os.path.exists(license_path):
        texts = [read(license_path)]
    elif previous and previous["version"] == version:
        return previous
    else:
        sys.exit("no SwiftTerm checkout: build the app once, then run this again")
    return {"name": "SwiftTerm", "version": version, "license": "MIT",
            "url": "https://github.com/migueldeicaza/SwiftTerm", "texts": texts}


def main():
    try:
        with open(OUT) as file:
            old = json.load(file)
        previous = next((entry for entry in old["packages"] if entry["name"] == "SwiftTerm"), None)
        if previous:
            previous = dict(previous, texts=[old["texts"][key] for key in previous["texts"]])
    except FileNotFoundError:
        previous = None

    entries = [swiftterm(previous)]
    for package in rust_packages():
        license, texts = crate_texts(package)
        entries.append({
            "name": package["name"], "version": package["version"], "license": license,
            "url": package["repository"] or f"https://crates.io/crates/{package['name']}",
            "texts": texts,
        })
    entries.append({
        "name": "Simple Icons", "version": "", "license": "CC0-1.0",
        "url": "https://simpleicons.org",
        "texts": ["The system icons of the hosts come from Simple Icons "
                  "(https://github.com/simple-icons/simple-icons), dedicated to the public "
                  "domain under CC0 1.0 Universal: "
                  "https://creativecommons.org/publicdomain/zero/1.0/\n"],
    })

    # Each text once: most crates share the standard Apache text.
    texts = {}
    for entry in entries:
        keys = []
        for text in entry["texts"]:
            key = hashlib.sha256(text.encode()).hexdigest()[:16]
            texts[key] = text
            keys.append(key)
        entry["texts"] = keys
    entries.sort(key=lambda entry: (entry["name"].lower(), entry["version"]))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as file:
        json.dump({"packages": entries, "texts": texts}, file, ensure_ascii=False, indent=1,
                  sort_keys=True)
        file.write("\n")
    print(f"{len(entries)} packages, {len(texts)} license texts in {OUT}")


main()
