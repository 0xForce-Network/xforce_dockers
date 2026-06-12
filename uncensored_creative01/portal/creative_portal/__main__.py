from __future__ import annotations

import argparse

import uvicorn


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="xforce-creative-portal")
    sub = parser.add_subparsers(dest="subcommand")
    serve = sub.add_parser("serve", help="run the creative suite portal")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8090)
    serve.add_argument("--log-level", default="info")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    subcommand = args.subcommand or "serve"
    if subcommand == "serve":
        uvicorn.run("creative_portal.app:create_app", host=args.host, port=args.port, factory=True, log_level=args.log_level)
        return 0
    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
