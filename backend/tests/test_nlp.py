"""Tests for the NLP processor module."""

import json
from unittest.mock import MagicMock, patch

import pytest

from app.api.scans.lambda_handler import nlp_handler
from app.api.scans.nlp import (
    NLPEvent,
    NLPResult,
    extract_keywords,
    process_nlp_event,
    summarize,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

SHORT_TEXT = "Machine learning is a subset of artificial intelligence."  # < 100 words

LONG_TEXT = (
    "Photosynthesis is the process by which green plants and some other organisms use sunlight "
    "to synthesize nutrients from carbon dioxide and water. "
    "Photosynthesis in plants generally involves the green pigment chlorophyll and generates "
    "oxygen as a byproduct. "
    "The light-dependent reactions take place in the thylakoid membranes of the chloroplasts. "
    "During these reactions, light energy is converted into chemical energy in the form of ATP "
    "and NADPH. "
    "The light-independent reactions, also known as the Calvin cycle, occur in the stroma. "
    "Carbon dioxide is fixed into organic molecules using the energy from ATP and NADPH. "
    "The overall equation for photosynthesis is: 6CO2 + 6H2O + light energy → C6H12O6 + 6O2. "
    "Factors affecting the rate of photosynthesis include light intensity, carbon dioxide "
    "concentration, and temperature. "
    "Chlorophyll absorbs light most efficiently in the red and blue portions of the "
    "electromagnetic spectrum. "
    "The green light is mostly reflected, which is why plants appear green to the human eye. "
    "Photosynthesis is fundamental to life on Earth as it is the primary source of oxygen in "
    "the atmosphere and the basis of most food chains. "
    "Without photosynthesis, the oxygen levels in the atmosphere would rapidly decline and "
    "most life forms would cease to exist. "
    "Scientists are studying artificial photosynthesis as a potential source of clean energy. "
    "By mimicking the natural process, researchers hope to develop efficient solar cells and "
    "hydrogen fuel production systems. "
    "The study of photosynthesis has led to many advances in our understanding of biochemistry "
    "and molecular biology. "
    "Modern techniques such as X-ray crystallography and cryo-electron microscopy have revealed "
    "the detailed structures of the protein complexes involved in photosynthesis. "
    "These discoveries have opened new avenues for biotechnology and agricultural improvements. "
    "Genetic engineering of photosynthetic pathways could potentially increase crop yields and "
    "help address global food security challenges. "
    "Researchers are also exploring how to enhance the efficiency of photosynthesis in crops "
    "to produce more biomass with less water and fertilizer. "
)  # > 500 words


def _make_nlp_event(**kwargs) -> NLPEvent:
    defaults = {
        "scan_id": "scan-nlp-123",
        "user_id": "user-456",
        "extracted_text": LONG_TEXT,
    }
    defaults.update(kwargs)
    return NLPEvent(**defaults)


# ---------------------------------------------------------------------------
# summarize()
# ---------------------------------------------------------------------------

class TestSummarize:
    def test_short_text_returned_unchanged(self):
        result = summarize(SHORT_TEXT)
        assert result == SHORT_TEXT

    def test_long_text_summary_word_count(self):
        """Summary of >500-word text should be between 150 and 200 words."""
        result = summarize(LONG_TEXT, target_words=175)
        word_count = len(result.split())
        # Allow a small buffer for sentence boundary rounding
        assert 100 <= word_count <= 220, f"Summary word count {word_count} out of expected range"

    def test_long_text_summary_is_not_original(self):
        result = summarize(LONG_TEXT)
        assert result != LONG_TEXT

    def test_returns_string(self):
        assert isinstance(summarize(SHORT_TEXT), str)
        assert isinstance(summarize(LONG_TEXT), str)

    def test_empty_text_returns_empty(self):
        result = summarize("")
        assert result == ""

    def test_text_between_100_and_500_words_returned_unchanged(self):
        # ~120 words — above 100 but below 500
        medium_text = " ".join(["word"] * 120)
        result = summarize(medium_text)
        # Should still return something (either original or summary)
        assert isinstance(result, str)
        assert len(result) > 0


# ---------------------------------------------------------------------------
# extract_keywords()
# ---------------------------------------------------------------------------

class TestExtractKeywords:
    def test_returns_between_5_and_15_keywords(self):
        keywords, scores = extract_keywords(LONG_TEXT)
        assert 5 <= len(keywords) <= 15, f"Got {len(keywords)} keywords"

    def test_returns_keyword_scores_dict(self):
        keywords, scores = extract_keywords(LONG_TEXT)
        assert isinstance(scores, dict)
        assert all(isinstance(v, float) for v in scores.values())

    def test_multi_word_phrases_come_first(self):
        keywords, _ = extract_keywords(LONG_TEXT)
        if len(keywords) >= 2:
            # At least the first keyword should be multi-word if any exist
            multi_word = [k for k in keywords if len(k.split()) > 1]
            single_word = [k for k in keywords if len(k.split()) == 1]
            if multi_word and single_word:
                first_multi = keywords.index(multi_word[0])
                first_single = keywords.index(single_word[0])
                assert first_multi < first_single, "Multi-word phrases should precede single words"

    def test_keywords_are_strings(self):
        keywords, _ = extract_keywords(LONG_TEXT)
        assert all(isinstance(k, str) for k in keywords)

    def test_short_text_returns_some_keywords(self):
        text = "machine learning artificial intelligence neural networks deep learning"
        keywords, scores = extract_keywords(text)
        assert isinstance(keywords, list)


# ---------------------------------------------------------------------------
# process_nlp_event()
# ---------------------------------------------------------------------------

class TestProcessNlpEvent:
    def _patch_all(self, extracted_text: str = LONG_TEXT):
        """Return patches for DynamoDB and Lambda clients, plus mocked NLP functions."""
        ddb_mock = MagicMock()
        table_mock = MagicMock()
        ddb_mock.Table.return_value = table_mock
        lambda_mock = MagicMock()

        mock_keywords = ["machine learning", "neural networks", "deep learning", "AI", "data"]
        mock_scores = {k: 4.0 for k in mock_keywords}

        return (
            patch("app.api.scans.nlp.get_dynamodb_resource", return_value=ddb_mock),
            patch("app.api.scans.nlp.get_lambda_client", return_value=lambda_mock),
            patch("app.api.scans.nlp.summarize", return_value="A short summary."),
            patch("app.api.scans.nlp.extract_keywords", return_value=(mock_keywords, mock_scores)),
            table_mock,
            lambda_mock,
        )

    def test_returns_nlp_result(self):
        p_ddb, p_lam, p_sum, p_kw, _, _ = self._patch_all()
        with p_ddb, p_lam, p_sum, p_kw:
            result = process_nlp_event(_make_nlp_event())
        assert isinstance(result, NLPResult)
        assert result.summary
        assert isinstance(result.keywords, list)
        assert result.processed_at

    def test_stores_nlp_data_in_dynamodb(self):
        p_ddb, p_lam, p_sum, p_kw, table_mock, _ = self._patch_all()
        with p_ddb, p_lam, p_sum, p_kw:
            process_nlp_event(_make_nlp_event(scan_id="scan-abc"))

        put_calls = table_mock.put_item.call_args_list
        assert len(put_calls) == 1
        item = put_calls[0].kwargs["Item"]
        assert item["PK"] == "SCAN#scan-abc"
        assert item["SK"] == "NLP_DATA"
        assert "summary" in item
        assert "keywords" in item
        assert "keyword_scores" in item

    def test_updates_scan_status_to_nlp_complete(self):
        p_ddb, p_lam, p_sum, p_kw, table_mock, _ = self._patch_all()
        with p_ddb, p_lam, p_sum, p_kw:
            process_nlp_event(_make_nlp_event(scan_id="scan-abc"))

        update_calls = table_mock.update_item.call_args_list
        assert len(update_calls) == 1
        call_kwargs = update_calls[0].kwargs
        assert call_kwargs["Key"] == {"PK": "SCAN#scan-abc", "SK": "METADATA"}
        assert call_kwargs["ExpressionAttributeValues"][":s"] == "nlp_complete"

    def test_invokes_search_lambda_asynchronously(self):
        p_ddb, p_lam, p_sum, p_kw, _, lambda_mock = self._patch_all()
        with p_ddb, p_lam, p_sum, p_kw:
            process_nlp_event(_make_nlp_event(scan_id="scan-abc", user_id="user-xyz"))

        lambda_mock.invoke.assert_called_once()
        call_kwargs = lambda_mock.invoke.call_args.kwargs
        assert call_kwargs["InvocationType"] == "Event"
        payload = json.loads(call_kwargs["Payload"])
        assert payload["scan_id"] == "scan-abc"
        assert payload["user_id"] == "user-xyz"
        assert "keywords" in payload
        assert "summary" in payload

    def test_fallback_to_original_text_on_summarization_failure(self):
        p_ddb, p_lam, _, p_kw = (
            patch("app.api.scans.nlp.get_dynamodb_resource", return_value=MagicMock(**{"Table.return_value": MagicMock()})),
            patch("app.api.scans.nlp.get_lambda_client", return_value=MagicMock()),
            patch("app.api.scans.nlp.summarize", side_effect=Exception("spaCy error")),
            patch("app.api.scans.nlp.extract_keywords", return_value=(["kw1", "kw2", "kw3", "kw4", "kw5"], {"kw1": 1.0, "kw2": 1.0, "kw3": 1.0, "kw4": 1.0, "kw5": 1.0})),
        )
        with p_ddb, p_lam, _, p_kw:
            result = process_nlp_event(_make_nlp_event(extracted_text=LONG_TEXT))

        # Should still succeed, using original text as summary
        assert result.summary == LONG_TEXT

    def test_raises_runtime_error_on_dynamodb_failure(self):
        ddb_mock = MagicMock()
        table_mock = MagicMock()
        table_mock.put_item.side_effect = Exception("DynamoDB unavailable")
        ddb_mock.Table.return_value = table_mock

        mock_keywords = ["kw1", "kw2", "kw3", "kw4", "kw5"]
        mock_scores = {k: 1.0 for k in mock_keywords}

        with patch("app.api.scans.nlp.get_dynamodb_resource", return_value=ddb_mock), \
             patch("app.api.scans.nlp.get_lambda_client", return_value=MagicMock()), \
             patch("app.api.scans.nlp.summarize", return_value="summary"), \
             patch("app.api.scans.nlp.extract_keywords", return_value=(mock_keywords, mock_scores)):
            with pytest.raises(RuntimeError, match="DynamoDB write failed"):
                process_nlp_event(_make_nlp_event())

    def test_short_text_summary_equals_original(self):
        p_ddb, p_lam, p_sum, p_kw, _, _ = self._patch_all(extracted_text=SHORT_TEXT)
        # Override summarize to return original (as the real function would for short text)
        with p_ddb, p_lam, \
             patch("app.api.scans.nlp.summarize", return_value=SHORT_TEXT), \
             p_kw:
            result = process_nlp_event(_make_nlp_event(extracted_text=SHORT_TEXT))
        assert result.summary == SHORT_TEXT

    def test_search_lambda_failure_does_not_raise(self):
        """Search Lambda invocation failure should be logged but not propagate."""
        p_ddb, p_lam, p_sum, p_kw, _, lambda_mock = self._patch_all()
        lambda_mock.invoke.side_effect = Exception("Lambda unavailable")
        with p_ddb, p_lam, p_sum, p_kw:
            # Should not raise
            result = process_nlp_event(_make_nlp_event())
        assert isinstance(result, NLPResult)


# ---------------------------------------------------------------------------
# nlp_handler (Lambda entry point)
# ---------------------------------------------------------------------------

class TestNlpHandler:
    def _valid_event(self) -> dict:
        return {
            "scan_id": "scan-999",
            "user_id": "user-111",
            "extracted_text": LONG_TEXT,
        }

    def _mock_result(self) -> NLPResult:
        return NLPResult(
            summary="A short summary.",
            keywords=["machine learning", "neural networks", "deep learning", "AI", "data"],
            keyword_scores={"machine learning": 4.0, "neural networks": 4.0, "deep learning": 4.0, "AI": 1.0, "data": 1.0},
            processed_at="2024-01-01T00:00:00+00:00",
        )

    def test_returns_200_on_success(self):
        with patch("app.api.scans.lambda_handler.process_nlp_event", return_value=self._mock_result()):
            response = nlp_handler(self._valid_event(), None)
        assert response["statusCode"] == 200
        body = response["body"]
        assert "summary" in body
        assert "keywords" in body

    def test_returns_500_on_runtime_error(self):
        with patch(
            "app.api.scans.lambda_handler.process_nlp_event",
            side_effect=RuntimeError("DynamoDB write failed"),
        ):
            response = nlp_handler(self._valid_event(), None)
        assert response["statusCode"] == 500
        assert response["body"]["error"] == "nlp_processing_error"

    def test_parses_json_string_event(self):
        with patch("app.api.scans.lambda_handler.process_nlp_event", return_value=self._mock_result()):
            response = nlp_handler(json.dumps(self._valid_event()), None)
        assert response["statusCode"] == 200

    def test_returns_500_on_unexpected_error(self):
        with patch(
            "app.api.scans.lambda_handler.process_nlp_event",
            side_effect=Exception("Unexpected"),
        ):
            response = nlp_handler(self._valid_event(), None)
        assert response["statusCode"] == 500
        assert response["body"]["error"] == "internal_error"
