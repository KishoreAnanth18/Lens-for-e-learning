"""Tests for the Search orchestrator module."""

import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.api.scans.lambda_handler import search_handler
from app.api.scans.search import (
    ArticleResource,
    SearchEvent,
    SearchResult,
    VideoResource,
    WebsiteResource,
    _deduplicate_by_url,
    _parse_articles,
    _parse_websites,
    build_search_query,
    process_search_event,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

KEYWORDS = [
    "photosynthesis light reactions",
    "chlorophyll absorption spectrum",
    "Calvin cycle carbon fixation",
    "ATP NADPH production",
    "oxygen byproduct",
]

SUMMARY = "Photosynthesis converts light energy into chemical energy using chlorophyll."


def _make_search_event(**kwargs) -> SearchEvent:
    defaults = {
        "scan_id": "scan-search-123",
        "user_id": "user-456",
        "keywords": KEYWORDS,
        "summary": SUMMARY,
    }
    defaults.update(kwargs)
    return SearchEvent(**defaults)


def _make_videos(n: int = 3) -> list[VideoResource]:
    return [
        VideoResource(
            video_id=f"vid{i}",
            title=f"Video {i}",
            description=f"Description {i}",
            thumbnail_url=f"https://img.youtube.com/vi/vid{i}/default.jpg",
            channel_name=f"Channel {i}",
            url=f"https://www.youtube.com/watch?v=vid{i}",
        )
        for i in range(n)
    ]


def _make_article_items(n: int = 3) -> list[dict]:
    return [
        {
            "link": f"https://example.com/article{i}",
            "title": f"Article {i}",
            "snippet": f"Snippet {i}",
            "displayLink": "example.com",
        }
        for i in range(n)
    ]


def _make_website_items(n: int = 3) -> list[dict]:
    return [
        {
            "link": f"https://edu.org/page{i}",
            "title": f"Page {i}",
            "snippet": f"Snippet {i}",
            "displayLink": "edu.org",
        }
        for i in range(n)
    ]


# ---------------------------------------------------------------------------
# build_search_query()
# ---------------------------------------------------------------------------

class TestBuildSearchQuery:
    def test_prefers_multi_word_phrases(self):
        keywords = ["photosynthesis", "light reactions", "ATP", "Calvin cycle"]
        query = build_search_query(keywords, max_keywords=2)
        # Multi-word phrases should come first
        assert "light reactions" in query or "Calvin cycle" in query

    def test_respects_max_keywords(self):
        query = build_search_query(KEYWORDS, max_keywords=2)
        # Should use at most 2 keywords
        assert len(query.split()) <= 6  # 2 multi-word phrases of up to 3 words each

    def test_empty_keywords_returns_empty_string(self):
        assert build_search_query([]) == ""

    def test_single_keyword(self):
        query = build_search_query(["photosynthesis"])
        assert query == "photosynthesis"


# ---------------------------------------------------------------------------
# _parse_articles() / _parse_websites()
# ---------------------------------------------------------------------------

class TestParsers:
    def test_parse_articles_returns_article_resources(self):
        items = _make_article_items(3)
        articles = _parse_articles(items)
        assert len(articles) == 3
        assert all(isinstance(a, ArticleResource) for a in articles)
        assert articles[0].url == "https://example.com/article0"
        assert articles[0].source == "example.com"

    def test_parse_articles_skips_items_without_url(self):
        items = [{"title": "No URL", "snippet": "test", "displayLink": "x.com"}]
        articles = _parse_articles(items)
        assert len(articles) == 0

    def test_parse_websites_returns_website_resources(self):
        items = _make_website_items(3)
        websites = _parse_websites(items)
        assert len(websites) == 3
        assert all(isinstance(w, WebsiteResource) for w in websites)
        assert websites[0].domain == "edu.org"

    def test_parse_websites_extracts_domain(self):
        items = [{"link": "https://www.khanacademy.org/science/biology", "title": "Khan", "snippet": "bio"}]
        websites = _parse_websites(items)
        assert websites[0].domain == "www.khanacademy.org"


# ---------------------------------------------------------------------------
# _deduplicate_by_url()
# ---------------------------------------------------------------------------

class TestDeduplication:
    def test_removes_duplicate_urls(self):
        videos = _make_videos(3)
        # Add a duplicate
        duplicate = VideoResource(**videos[0].model_dump())
        result = _deduplicate_by_url(videos + [duplicate])
        assert len(result) == 3

    def test_preserves_order(self):
        videos = _make_videos(3)
        result = _deduplicate_by_url(videos)
        assert [v.url for v in result] == [v.url for v in videos]

    def test_empty_list(self):
        assert _deduplicate_by_url([]) == []


# ---------------------------------------------------------------------------
# process_search_event()
# ---------------------------------------------------------------------------

class TestProcessSearchEvent:
    def _patch_all(self, videos=None, article_items=None, website_items=None):
        videos = videos if videos is not None else _make_videos(3)
        article_items = article_items if article_items is not None else _make_article_items(3)
        website_items = website_items if website_items is not None else _make_website_items(3)

        ddb_mock = MagicMock()
        table_mock = MagicMock()
        ddb_mock.Table.return_value = table_mock

        return (
            patch("app.api.scans.search.get_dynamodb_resource", return_value=ddb_mock),
            patch("app.api.scans.search._run_parallel_searches",
                  return_value=(videos, _parse_articles(article_items), _parse_websites(website_items))),
            table_mock,
        )

    def test_returns_search_result(self):
        p_ddb, p_search, _ = self._patch_all()
        with p_ddb, p_search:
            result = process_search_event(_make_search_event())
        assert isinstance(result, SearchResult)
        assert isinstance(result.videos, list)
        assert isinstance(result.articles, list)
        assert isinstance(result.websites, list)
        assert result.processed_at

    def test_result_contains_all_three_categories(self):
        p_ddb, p_search, _ = self._patch_all()
        with p_ddb, p_search:
            result = process_search_event(_make_search_event())
        # All three categories must be present (may be empty lists)
        assert hasattr(result, "videos")
        assert hasattr(result, "articles")
        assert hasattr(result, "websites")

    def test_stores_results_in_dynamodb(self):
        p_ddb, p_search, table_mock = self._patch_all()
        with p_ddb, p_search:
            process_search_event(_make_search_event(scan_id="scan-abc"))

        put_calls = table_mock.put_item.call_args_list
        assert len(put_calls) == 1
        item = put_calls[0].kwargs["Item"]
        assert item["PK"] == "SCAN#scan-abc"
        assert item["SK"] == "RESULTS"
        assert "videos" in item
        assert "articles" in item
        assert "websites" in item

    def test_updates_scan_status_to_complete(self):
        p_ddb, p_search, table_mock = self._patch_all()
        with p_ddb, p_search:
            process_search_event(_make_search_event(scan_id="scan-abc"))

        update_calls = table_mock.update_item.call_args_list
        assert len(update_calls) == 1
        call_kwargs = update_calls[0].kwargs
        assert call_kwargs["Key"] == {"PK": "SCAN#scan-abc", "SK": "METADATA"}
        assert call_kwargs["ExpressionAttributeValues"][":s"] == "complete"

    def test_caps_results_at_10_per_category(self):
        # Provide 15 items per category
        p_ddb, p_search, _ = self._patch_all(
            videos=_make_videos(15),
            article_items=_make_article_items(15),
            website_items=_make_website_items(15),
        )
        with p_ddb, p_search:
            result = process_search_event(_make_search_event())
        assert len(result.videos) <= 10
        assert len(result.articles) <= 10
        assert len(result.websites) <= 10

    def test_handles_empty_results_gracefully(self):
        p_ddb, p_search, _ = self._patch_all(videos=[], article_items=[], website_items=[])
        with p_ddb, p_search:
            result = process_search_event(_make_search_event())
        assert result.videos == []
        assert result.articles == []
        assert result.websites == []

    def test_raises_runtime_error_on_dynamodb_failure(self):
        ddb_mock = MagicMock()
        table_mock = MagicMock()
        table_mock.put_item.side_effect = Exception("DynamoDB unavailable")
        ddb_mock.Table.return_value = table_mock

        with patch("app.api.scans.search.get_dynamodb_resource", return_value=ddb_mock), \
             patch("app.api.scans.search._run_parallel_searches",
                   return_value=(_make_videos(3), _parse_articles(_make_article_items(3)), _parse_websites(_make_website_items(3)))):
            with pytest.raises(RuntimeError, match="DynamoDB write failed"):
                process_search_event(_make_search_event())

    def test_deduplicates_results(self):
        # Provide duplicate videos
        videos = _make_videos(3)
        duplicate = VideoResource(**videos[0].model_dump())
        all_videos = videos + [duplicate]

        p_ddb, _, table_mock = self._patch_all()
        with patch("app.api.scans.search.get_dynamodb_resource", return_value=MagicMock(**{"Table.return_value": table_mock})), \
             patch("app.api.scans.search._run_parallel_searches",
                   return_value=(all_videos, [], [])):
            result = process_search_event(_make_search_event())
        assert len(result.videos) == 3  # duplicate removed

    def test_search_queries_included_in_result(self):
        p_ddb, p_search, _ = self._patch_all()
        with p_ddb, p_search:
            result = process_search_event(_make_search_event())
        assert isinstance(result.search_queries, list)
        assert len(result.search_queries) > 0


# ---------------------------------------------------------------------------
# search_handler (Lambda entry point)
# ---------------------------------------------------------------------------

class TestSearchHandler:
    def _valid_event(self) -> dict:
        return {
            "scan_id": "scan-999",
            "user_id": "user-111",
            "keywords": KEYWORDS,
            "summary": SUMMARY,
        }

    def _mock_result(self) -> SearchResult:
        return SearchResult(
            videos=_make_videos(3),
            articles=_parse_articles(_make_article_items(3)),
            websites=_parse_websites(_make_website_items(3)),
            search_queries=["photosynthesis light reactions"],
            processed_at="2024-01-01T00:00:00+00:00",
        )

    def test_returns_200_on_success(self):
        with patch("app.api.scans.lambda_handler.process_search_event", return_value=self._mock_result()):
            response = search_handler(self._valid_event(), None)
        assert response["statusCode"] == 200
        body = response["body"]
        assert "videos" in body
        assert "articles" in body
        assert "websites" in body

    def test_returns_500_on_runtime_error(self):
        with patch(
            "app.api.scans.lambda_handler.process_search_event",
            side_effect=RuntimeError("DynamoDB write failed"),
        ):
            response = search_handler(self._valid_event(), None)
        assert response["statusCode"] == 500
        assert response["body"]["error"] == "search_processing_error"

    def test_parses_json_string_event(self):
        with patch("app.api.scans.lambda_handler.process_search_event", return_value=self._mock_result()):
            response = search_handler(json.dumps(self._valid_event()), None)
        assert response["statusCode"] == 200

    def test_returns_500_on_unexpected_error(self):
        with patch(
            "app.api.scans.lambda_handler.process_search_event",
            side_effect=Exception("Unexpected"),
        ):
            response = search_handler(self._valid_event(), None)
        assert response["statusCode"] == 500
        assert response["body"]["error"] == "internal_error"

    def test_returns_422_on_validation_error(self):
        # Missing required fields
        with patch(
            "app.api.scans.lambda_handler.process_search_event",
            side_effect=ValueError("missing field"),
        ):
            response = search_handler(self._valid_event(), None)
        assert response["statusCode"] == 422
        assert response["body"]["error"] == "search_validation_error"
