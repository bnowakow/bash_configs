#!/usr/bin/env python3
"""Submit one URL to every discoverable IndexNow endpoint (Python 3 stdlib only)."""

import argparse
import json
import math
import os
from pathlib import Path
import re
import secrets
import shlex
import socket
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler


REGISTRY = "https://www.indexnow.org/searchengines.json"
# Official FAQ fallback if discovery or an individual metadata request fails:
# https://www.indexnow.org/faq (checked 2026-10-22).
FALLBACK = {
    "amazonbot": "https://indexnow.amazonbot.amazon/indexnow",
    "bing": "https://www.bing.com/indexnow",
    "naver": "https://searchadvisor.naver.com/indexnow",
    "seznam": "https://search.seznam.cz/indexnow",
    "yandex": "https://yandex.com/indexnow",
    "yep": "https://indexnow.yep.com/indexnow",
}
STATUS = {
    200: "received (indexing is not guaranteed)",
    202: "received; key validation pending",
    400: "invalid request format",
    403: "key verification failed; check the hosted key file",
    422: "URL host, key, or key-file scope is invalid",
    429: "rate limited; retry later",
}


def colored(text, color, stream=None):
    stream = sys.stdout if stream is None else stream
    if not stream.isatty() or "NO_COLOR" in os.environ:
        return str(text)
    codes = {"blue": 34, "red": 31, "yellow": 33}
    return f"\033[{codes[color]}m{text}\033[0m"


def warning(message, engine=None):
    prefix = colored("Warning: ", "yellow", sys.stderr)
    if engine is not None:
        prefix += colored(engine, "blue", sys.stderr) + " "
    print(prefix + colored(message, "yellow", sys.stderr), file=sys.stderr)


class NoRedirect(HTTPRedirectHandler):
    """Do not silently turn a redirected submission into a GET or leak its key."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def web_url(value, https_only=False):
    try:
        parsed = urlsplit(value)
        allowed = ("https",) if https_only else ("http", "https")
        if (parsed.scheme not in allowed or not parsed.hostname
                or parsed.username is not None or parsed.password is not None
                or "#" in value or re.search(r"\s", value)):
            raise ValueError("expected an absolute HTTP(S) URL without credentials or fragment")
        parsed.port  # Validate the port as well.
        value.encode("ascii")
    except (ValueError, UnicodeError) as error:
        raise ValueError(f"invalid URL: {error}; percent-encode non-ASCII characters") from error
    return parsed


def fetch_json(url, timeout):
    web_url(url, https_only=True)
    request = Request(url, headers={"User-Agent": "submit-indexnow/1.0"})
    with build_opener(NoRedirect()).open(request, timeout=timeout) as response:
        return json.load(response)


def discover(timeout):
    endpoints = {"IndexNow global": "https://api.indexnow.org/indexnow"}
    endpoints.update(FALLBACK)
    incomplete = False
    print(f"Discovering IndexNow engines from {REGISTRY} "
          f"(timeout: {timeout:g}s per request)...", flush=True)
    try:
        registry = fetch_json(REGISTRY, timeout)
        if not isinstance(registry, dict) or not registry:
            raise ValueError("expected a nonempty registry object")
    except (OSError, URLError, ValueError) as error:
        warning(f"registry unavailable ({error}); using FAQ endpoints. "
                "Additional participants may be missed.")
        return endpoints, True
    for engine, metadata_url in registry.items():
        print(f"{colored(engine, 'blue')}: checking endpoint metadata...", flush=True)
        try:
            if not isinstance(metadata_url, str):
                raise ValueError("metadata URL is not a string")
            metadata = fetch_json(metadata_url, timeout)
            # The official registry supplies the trusted metadata URL and label.
            # Some participants publish an id that differs from that label.
            if not isinstance(metadata, dict):
                raise ValueError("expected a metadata object")
            endpoint = metadata.get("api")
            if not isinstance(endpoint, str):
                raise ValueError("metadata has no API endpoint")
            web_url(endpoint, https_only=True)
            endpoints[engine] = endpoint
        except (OSError, URLError, ValueError) as error:
            fallback = engine in FALLBACK
            warning(f"discovery failed ({error}); "
                    + ("using FAQ endpoint." if fallback else "no known fallback."),
                    engine=engine)
            incomplete |= not fallback
    return endpoints, incomplete


def positive_timeout(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("must be a finite number greater than zero")
    return number


def offer_key_generation(args, target, parser):
    try:
        answer = input("No IndexNow key provided. Generate a key and upload file? [y/N] ")
    except EOFError:
        parser.error("no input available; provide --key or INDEXNOW_KEY")
    if answer.strip().lower() not in ("y", "yes"):
        print("No key generated. Provide --key or INDEXNOW_KEY to submit.")
        return 1

    key = secrets.token_hex(16)
    path = Path.cwd() / f"{key}.txt"
    try:
        with path.open("x", encoding="utf-8") as key_file:
            key_file.write(key)
    except OSError as error:
        print(f"Cannot create key file: {error}", file=sys.stderr)
        return 1

    location = args.key_location or f"{target.scheme}://{target.netloc}/{key}.txt"
    print(f"Created: {path}")
    print(f"Upload this file so it is publicly accessible at: {location}")
    print("No URL submitted. After uploading, run:")
    command = [sys.executable, str(Path(__file__).resolve()), "--key", key]
    if args.key_location:
        command.extend(["--key-location", args.key_location])
    command.extend(["--timeout", str(args.timeout)])
    if args.dry_run:
        command.append("--dry-run")
    if args.skip_discovery:
        command.append("--skip-discovery")
    command.append(args.url)
    print(" ".join(shlex.quote(part) for part in command))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog="First host <key>.txt containing your key at your website root. "
               "IndexNow engines share submissions; a single accepted endpoint "
               "also reaches the participating network.",
    )
    parser.add_argument("url", help="absolute, percent-encoded URL to submit")
    parser.add_argument("--key", default=os.environ.get("INDEXNOW_KEY"),
                        help="ownership key (defaults to INDEXNOW_KEY)")
    parser.add_argument("--key-location", default=os.environ.get("INDEXNOW_KEY_LOCATION"),
                        help="hosted key-file URL (defaults to INDEXNOW_KEY_LOCATION)")
    parser.add_argument("--timeout", type=positive_timeout, default=15,
                        help="timeout in seconds per network request (default: 15)")
    parser.add_argument("--dry-run", action="store_true",
                        help="discover and print endpoints without submitting")
    parser.add_argument("--skip-discovery", action="store_true",
                        help="use known FAQ endpoints without fetching the registry "
                             "(may miss additional participants)")
    args = parser.parse_args(argv)
    if args.key and not re.fullmatch(r"[a-zA-Z0-9-]{8,128}", args.key):
        parser.error("provide --key or INDEXNOW_KEY: 8-128 letters, digits, or dashes")
    try:
        target = web_url(args.url)
        if args.key_location:
            location = web_url(args.key_location)
            if location.netloc.lower() != target.netloc.lower():
                raise ValueError("key location must use the submitted URL's host and port")
    except ValueError as error:
        parser.error(str(error))

    if not args.key:
        return offer_key_generation(args, target, parser)

    payload = {"host": target.netloc, "key": args.key, "urlList": [args.url]}
    if args.key_location:
        payload["keyLocation"] = args.key_location
    data = json.dumps(payload).encode("utf-8")
    if args.skip_discovery:
        endpoints = {"IndexNow global": "https://api.indexnow.org/indexnow", **FALLBACK}
        incomplete = False
        warning("Skipping discovery; using known FAQ endpoints. "
                "Additional participants may be missed.")
    else:
        endpoints, incomplete = discover(args.timeout)
    failures = 0
    accepted = 0
    seen = set()
    opener = build_opener(NoRedirect())
    for name, endpoint in endpoints.items():
        if endpoint in seen:
            continue
        seen.add(endpoint)
        label = colored(name, "blue")
        if args.dry_run:
            print(f"{label}: would POST to {endpoint}")
            continue
        request = Request(endpoint, data=data, headers={
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "submit-indexnow/1.0",
        }, method="POST")
        print(f"{label}: submitting to {endpoint} "
              f"(timeout: {args.timeout:g}s)...", flush=True)
        try:
            with opener.open(request, timeout=args.timeout) as response:
                status = response.status
        except HTTPError as error:
            status = error.code
            error.close()
        except (OSError, URLError, ValueError) as error:
            reason = error.reason if isinstance(error, URLError) else error
            if isinstance(reason, socket.gaierror):
                detail = (f"DNS lookup failed for {urlsplit(endpoint).hostname}; "
                          "could not resolve the advertised endpoint")
            else:
                detail = str(error)
            print(f"{label}: {colored(f'FAILED ({detail})', 'red')}", flush=True)
            failures += 1
            continue
        success = status in (200, 202)
        accepted += success
        failures += not success
        code = colored(f"HTTP {status}", "yellow" if success else "red")
        print(f"{label}: {code} — {STATUS.get(status, 'unexpected response')}",
              flush=True)
    if not args.dry_run:
        print(f"Received by {accepted}/{len(seen)} endpoints; {failures} failed.")
    return 1 if failures or incomplete else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
