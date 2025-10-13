#!/usr/bin/env python3
"""
Gnosis Crawl MCP Bridge
=======================

Exposes Wraith crawler capabilities to Codex via MCP, mirroring
the MCP style used in this repo (FastMCP over stdio).

Tools:
  - crawl_url: fetch markdown from a single URL
  - crawl_batch: process multiple URLs (optionally async/collated)
  - raw_html: fetch raw HTML without markdown conversion
  - set_auth_token: save Wraith API token to .wraithenv
  - crawl_status: report configuration (base URL, token presence)

Env/config:
  - WRAITH_AUTH_TOKEN        (preferred if present)
  - GNOSIS_CRAWL_BASE_URL    (overrides server URL)
  - .wraithenv file in repo root with line: WRAITH_AUTH_TOKEN=...

Defaults:
  - Remote: https://wraith.nuts.services
  - Local:  http://localhost:5678 (use_local_server=true)
"""

import os
from typing import Any, Dict, List, Optional

import aiohttp
from mcp.server.fastmcp import FastMCP, Context
from urllib.parse import urlparse

mcp = FastMCP("gnosis-crawl")


REMOTE_SERVER_URL = os.environ.get("GNOSIS_CRAWL_BASE_URL", "https://wraith.nuts.services").strip()
LOCAL_SERVER_URL = "http://localhost:5678"
WRAITH_ENV_FILE = os.path.join(os.getcwd(), ".wraithenv")


def _extract_domain(url: str) -> str:
    try:
        return urlparse(url).netloc.lower()
    except Exception:
        return "unknown"


def _get_auth_token() -> Optional[str]:
    # Env wins
    tok = os.environ.get("WRAITH_AUTH_TOKEN")
    if tok:
        return tok.strip()
    # Fallback to .wraithenv
    try:
        if os.path.exists(WRAITH_ENV_FILE):
            with open(WRAITH_ENV_FILE, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("WRAITH_AUTH_TOKEN="):
                        return line.split("=", 1)[1].strip()
    except Exception:
        pass
    return None


def _resolve_base_url(use_local_server: bool, server_url: Optional[str]) -> str:
    if server_url:
        return server_url
    return LOCAL_SERVER_URL if use_local_server else REMOTE_SERVER_URL


@mcp.tool()
async def set_auth_token(token: str, ctx: Context = None) -> Dict[str, Any]:
    """Save Wraith API token to .wraithenv in the repo root."""
    if not token:
        return {"success": False, "error": "No token provided"}
    try:
        with open(WRAITH_ENV_FILE, "w", encoding="utf-8") as f:
            f.write(f"WRAITH_AUTH_TOKEN={token}\n")
        return {"success": True, "message": "Saved token to .wraithenv", "file": WRAITH_ENV_FILE}
    except Exception as e:
        return {"success": False, "error": f"Failed to save token: {e}"}


@mcp.tool()
async def crawl_status(use_local_server: bool = False, server_url: Optional[str] = None) -> Dict[str, Any]:
    """Return effective server URL and whether an auth token is present."""
    base = _resolve_base_url(use_local_server, server_url)
    return {
        "success": True,
        "base_url": base,
        "token_present": _get_auth_token() is not None,
    }


@mcp.tool()
async def crawl_url(
    url: str,
    take_screenshot: bool = False,
    javascript_enabled: bool = False,
    markdown_extraction: str = "enhanced",
    use_local_server: bool = False,
    server_url: Optional[str] = None,
    timeout: int = 30,
    title: Optional[str] = None,
    ctx: Context = None,
) -> Dict[str, Any]:
    """Fetch markdown from a single URL via Wraith API."""
    if not url:
        return {"success": False, "error": "No URL provided"}

    base = _resolve_base_url(use_local_server, server_url)
    endpoint = f"{base}/api/markdown"

    if not title:
        title = f"Crawl: {_extract_domain(url)}"

    payload: Dict[str, Any] = {
        "url": url,
        "javascript_enabled": bool(javascript_enabled),
        "screenshot_mode": "full" if take_screenshot else None,
    }
    if markdown_extraction == "enhanced":
        payload["filter"] = "pruning"
        payload["filter_options"] = {"threshold": 0.48, "min_words": 2}

    headers: Dict[str, str] = {}
    tok = _get_auth_token()
    if tok:
        headers["Authorization"] = f"Bearer {tok}"

    try:
        timeout_cfg = aiohttp.ClientTimeout(total=max(5, int(timeout)))
        async with aiohttp.ClientSession(timeout=timeout_cfg) as session:
            async with session.post(endpoint, json=payload, headers=headers) as resp:
                if resp.status == 200:
                    return await resp.json()
                return {"success": False, "error": f"{resp.status}: {await resp.text()}"}
    except Exception as e:
        return {"success": False, "error": str(e)}


@mcp.tool()
async def crawl_batch(
    urls: List[str],
    javascript_enabled: bool = False,
    take_screenshot: bool = False,
    async_mode: bool = True,
    collate: bool = False,
    collate_title: Optional[str] = None,
    use_local_server: bool = False,
    server_url: Optional[str] = None,
    timeout: int = 60,
    ctx: Context = None,
) -> Dict[str, Any]:
    """Crawl multiple URLs in one call (optionally async/collated)."""
    if not urls:
        return {"success": False, "error": "No URLs provided"}
    if len(urls) > 50:
        return {"success": False, "error": "Maximum 50 URLs allowed per batch"}

    base = _resolve_base_url(use_local_server, server_url)
    endpoint = f"{base}/api/markdown"

    payload: Dict[str, Any] = {
        "urls": urls,
        "javascript_enabled": bool(javascript_enabled),
        "screenshot_mode": "full" if take_screenshot else None,
        "async": bool(async_mode),
        "collate": bool(collate),
    }
    if collate:
        payload["collate_options"] = {
            "title": collate_title or f"Batch Crawl Results ({len(urls)} URLs)",
            "add_toc": True,
            "add_source_headers": True,
        }

    headers: Dict[str, str] = {}
    tok = _get_auth_token()
    if tok:
        headers["Authorization"] = f"Bearer {tok}"

    try:
        timeout_cfg = aiohttp.ClientTimeout(total=max(10, int(timeout)))
        async with aiohttp.ClientSession(timeout=timeout_cfg) as session:
            async with session.post(endpoint, json=payload, headers=headers) as resp:
                if resp.status in (200, 202):
                    return await resp.json()
                return {"success": False, "error": f"{resp.status}: {await resp.text()}"}
    except Exception as e:
        return {"success": False, "error": str(e)}


@mcp.tool()
async def raw_html(
    url: str,
    javascript_enabled: bool = True,
    javascript_payload: Optional[str] = None,
    use_local_server: bool = False,
    server_url: Optional[str] = None,
    timeout: int = 30,
    ctx: Context = None,
) -> Dict[str, Any]:
    """Fetch raw HTML from a URL via Wraith API."""
    if not url:
        return {"success": False, "error": "No URL provided"}

    base = _resolve_base_url(use_local_server, server_url)
    endpoint = f"{base}/api/raw"

    payload: Dict[str, Any] = {
        "url": url,
        "javascript_enabled": bool(javascript_enabled),
    }
    if javascript_payload:
        payload["javascript_payload"] = javascript_payload

    headers: Dict[str, str] = {}
    tok = _get_auth_token()
    if tok:
        headers["Authorization"] = f"Bearer {tok}"

    try:
        timeout_cfg = aiohttp.ClientTimeout(total=max(5, int(timeout)))
        async with aiohttp.ClientSession(timeout=timeout_cfg) as session:
            async with session.post(endpoint, json=payload, headers=headers) as resp:
                if resp.status == 200:
                    return await resp.json()
                return {"success": False, "error": f"{resp.status}: {await resp.text()}"}
    except Exception as e:
        return {"success": False, "error": str(e)}


if __name__ == "__main__":
    mcp.run(transport="stdio")

