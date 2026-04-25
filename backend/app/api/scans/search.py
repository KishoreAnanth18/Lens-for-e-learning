"""Search orchestrator — queries YouTube and web search APIs for learning resources."""

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import httpx
from pydantic import BaseModel

from app.core.aws import get_dynamodb_resource
from app.core.config import settings

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------


class SearchEvent(BaseModel):
    scan_id: str
    user_id: str
    keywords: List[str]
    summary: str


class VideoResource(BaseModel):
    video_id: str
    title: str
    description: str
    thumbnail_url: str
    channel_name: str
    url: str


class ArticleResource(BaseModel):
    url: str
    title: str
    description: str
    source: str


class WebsiteResource(BaseModel):
    url: str
    title: str
    description: str
    domain: str


class SearchResult(BaseModel):
    videos: List[VideoResource]
    articles: List[ArticleResource]
    websites: List[WebsiteResource]
    search_queries: List[str]
    processed_at: str  # ISO 8601


# ---------------------------------------------------------------------------
# Query construction
# ---------------------------------------------------------------------------


def build_search_query(keywords: List[str], max_keywords: int = 3) -> str:
    """Build a search query from the top N keywords, preferring multi-word phrases."""
    if not keywords:
        return ""
    # Prefer multi-word phrases first, then single words
    multi = [k for k in keywords if len(k.split()) > 1]
    single = [k for k in keywords if len(k.split()) == 1]
    ordered = (multi + single)[:max_keywords]
    return " ".join(ordered)


# ---------------------------------------------------------------------------
# YouTube search
# ---------------------------------------------------------------------------


async def search_youtube(
    query: str,
    api_key: str,
    max_results: int = 10,
) -> List[VideoResource]:
    """Query YouTube Data API v3 for educational videos."""
    if not api_key or not query:
        return []

    params = {
        "part": "snippet",
        "q": query,
        "type": "video",
        "maxResults": max_results,
        "relevanceLanguage": "en",
        "videoEmbeddable": "true",
        "key": api_key,
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                "https://www.googleapis.com/youtube/v3/search",
                params=params,
            )
            response.raise_for_status()
            data = response.json()
    except Exception as exc:
        logger.warning("YouTube search failed for query '%s': %s", query, exc)
        return []

    videos = []
    for item in data.get("items", []):
        snippet = item.get("snippet", {})
        video_id = item.get("id", {}).get("videoId", "")
        if not video_id:
            continue
        videos.append(
            VideoResource(
                video_id=video_id,
                title=snippet.get("title", ""),
                description=snippet.get("description", ""),
                thumbnail_url=snippet.get("thumbnails", {}).get("default", {}).get("url", ""),
                channel_name=snippet.get("channelTitle", ""),
                url=f"https://www.youtube.com/watch?v={video_id}",
            )
        )
    return videos


# ---------------------------------------------------------------------------
# Google Custom Search (articles + websites)
# ---------------------------------------------------------------------------


async def search_google(
    query: str,
    api_key: str,
    search_engine_id: str,
    max_results: int = 10,
    search_type: str = "web",
) -> List[Dict[str, Any]]:
    """Query Google Custom Search API; returns raw result dicts."""
    if not api_key or not search_engine_id or not query:
        return []

    params = {
        "q": query,
        "key": api_key,
        "cx": search_engine_id,
        "num": min(max_results, 10),  # API max is 10 per request
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                "https://www.googleapis.com/customsearch/v1",
                params=params,
            )
            response.raise_for_status()
            data = response.json()
    except Exception as exc:
        logger.warning("Google search failed for query '%s': %s", query, exc)
        return []

    return data.get("items", [])


def _parse_articles(items: List[Dict[str, Any]]) -> List[ArticleResource]:
    articles = []
    for item in items:
        url = item.get("link", "")
        if not url:
            continue
        articles.append(
            ArticleResource(
                url=url,
                title=item.get("title", ""),
                description=item.get("snippet", ""),
                source=item.get("displayLink", ""),
            )
        )
    return articles


def _parse_websites(items: List[Dict[str, Any]]) -> List[WebsiteResource]:
    websites = []
    for item in items:
        url = item.get("link", "")
        if not url:
            continue
        from urllib.parse import urlparse
        domain = urlparse(url).netloc
        websites.append(
            WebsiteResource(
                url=url,
                title=item.get("title", ""),
                description=item.get("snippet", ""),
                domain=domain,
            )
        )
    return websites


# ---------------------------------------------------------------------------
# Deduplication
# ---------------------------------------------------------------------------


def _deduplicate_by_url(items: list) -> list:
    seen: set = set()
    result = []
    for item in items:
        url = getattr(item, "url", None)
        if url and url not in seen:
            seen.add(url)
            result.append(item)
    return result


# ---------------------------------------------------------------------------
# Main processing handler
# ---------------------------------------------------------------------------


def process_search_event(event: SearchEvent) -> SearchResult:
    """
    Full search pipeline:
    1. Build search query from keywords
    2. Execute parallel searches (YouTube, articles, websites)
    3. Deduplicate and cap results (max 10 per category)
    4. Store results in DynamoDB
    5. Update scan status to 'complete'
    """
    scan_id = event.scan_id
    query = build_search_query(event.keywords)
    article_query = query + " tutorial"
    website_query = query + " educational resource"
    search_queries = [q for q in [query, article_query, website_query] if q]

    # Run async searches synchronously (Lambda has no running event loop)
    videos, articles, websites = _run_parallel_searches(
        query=query,
        article_query=article_query,
        website_query=website_query,
    )

    # Deduplicate
    videos = _deduplicate_by_url(videos)
    articles = _deduplicate_by_url(articles)
    websites = _deduplicate_by_url(websites)

    # Cap at 10 per category
    videos = videos[:10]
    articles = articles[:10]
    websites = websites[:10]

    processed_at = datetime.now(timezone.utc).isoformat()

    # Persist to DynamoDB
    try:
        ddb = get_dynamodb_resource()
        table = ddb.Table(settings.DYNAMODB_TABLE_NAME)

        table.put_item(
            Item={
                "PK": f"SCAN#{scan_id}",
                "SK": "RESULTS",
                "videos": [v.model_dump() for v in videos],
                "articles": [a.model_dump() for a in articles],
                "websites": [w.model_dump() for w in websites],
                "total_results": len(videos) + len(articles) + len(websites),
                "search_queries": search_queries,
                "processed_at": processed_at,
            }
        )

        table.update_item(
            Key={"PK": f"SCAN#{scan_id}", "SK": "METADATA"},
            UpdateExpression="SET #s = :s, updated_at = :u",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":s": "complete",
                ":u": processed_at,
            },
        )
    except Exception as exc:
        raise RuntimeError(
            f"[scan_id={scan_id}] DynamoDB write failed: {exc}"
        ) from exc

    return SearchResult(
        videos=videos,
        articles=articles,
        websites=websites,
        search_queries=search_queries,
        processed_at=processed_at,
    )


def _run_parallel_searches(
    query: str,
    article_query: str,
    website_query: str,
) -> Tuple[List[VideoResource], List[ArticleResource], List[WebsiteResource]]:
    """Run all three searches concurrently using asyncio."""

    async def _gather():
        yt_task = search_youtube(
            query=query,
            api_key=settings.YOUTUBE_API_KEY,
        )
        article_task = search_google(
            query=article_query,
            api_key=settings.GOOGLE_SEARCH_API_KEY,
            search_engine_id=settings.GOOGLE_SEARCH_ENGINE_ID,
        )
        website_task = search_google(
            query=website_query,
            api_key=settings.GOOGLE_SEARCH_API_KEY,
            search_engine_id=settings.GOOGLE_SEARCH_ENGINE_ID,
        )
        return await asyncio.gather(yt_task, article_task, website_task)

    yt_results, article_items, website_items = asyncio.run(_gather())

    articles = _parse_articles(article_items)
    websites = _parse_websites(website_items)

    return yt_results, articles, websites
