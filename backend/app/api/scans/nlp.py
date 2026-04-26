"""NLP processor — summarizes extracted text and extracts keywords, stores results in DynamoDB."""

import json
import logging
import os
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

from pydantic import BaseModel

from app.core.aws import get_dynamodb_resource, get_lambda_client
from app.core.config import settings

logger = logging.getLogger(__name__)


def _ensure_nltk_data() -> None:
    """Download required NLTK corpora if not already present (Lambda cold start)."""
    import nltk

    for resource, path in [
        ("stopwords", "corpora/stopwords"),
        ("punkt_tab", "tokenizers/punkt_tab"),
    ]:
        try:
            nltk.data.find(path)
        except LookupError:
            nltk.download(resource, quiet=True)


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class NLPEvent(BaseModel):
    scan_id: str
    user_id: str
    extracted_text: str


class NLPResult(BaseModel):
    summary: str
    keywords: List[str]
    keyword_scores: Dict[str, float]
    processed_at: str  # ISO 8601


# ---------------------------------------------------------------------------
# spaCy model loading (cached in /tmp for Lambda warm starts)
# ---------------------------------------------------------------------------

_nlp = None


def _get_nlp():
    """Load and cache the spaCy model. Uses /tmp for Lambda warm-start caching."""
    global _nlp
    if _nlp is None:
        import spacy

        model_path = "/tmp/en_core_web_sm"
        if os.path.exists(model_path):
            _nlp = spacy.load(model_path)
        else:
            _nlp = spacy.load("en_core_web_sm")
            # Persist to /tmp so subsequent warm invocations skip the load
            try:
                _nlp.to_disk(model_path)
            except Exception:
                pass  # Non-fatal — model stays in memory
    return _nlp


# ---------------------------------------------------------------------------
# Summarization
# ---------------------------------------------------------------------------

def _word_count(text: str) -> int:
    return len(text.split())


def summarize(text: str, target_words: int = 175) -> str:
    """
    Summarize text using spaCy sentence scoring.

    - text < 100 words  → return original unchanged
    - text > 500 words  → extract top-ranked sentences up to ~target_words
    - otherwise         → return original unchanged
    """
    if _word_count(text) < 100:
        return text

    nlp = _get_nlp()
    doc = nlp(text)
    sentences = list(doc.sents)

    if not sentences:
        return text

    # Score sentences by sum of non-stop token ranks, normalised by sentence length
    scores: Dict = {}
    for sent in sentences:
        tokens = [t for t in sent if not t.is_stop and t.is_alpha]
        if not tokens:
            scores[sent] = 0.0
            continue
        score = sum(t.rank for t in tokens)
        scores[sent] = score / max(len(sent), 1)

    # Select top sentences until we reach the target word count
    ranked = sorted(sentences, key=lambda s: scores[s], reverse=True)
    summary_sents = []
    word_count = 0

    for sent in ranked:
        sent_words = len(sent.text.split())
        if word_count + sent_words <= target_words:
            summary_sents.append(sent)
            word_count += sent_words
        if word_count >= target_words:
            break

    if not summary_sents:
        # Fallback: just take the first sentence
        summary_sents = [sentences[0]]

    # Restore original document order
    summary_sents.sort(key=lambda s: s.start)
    return " ".join(str(s) for s in summary_sents)


# ---------------------------------------------------------------------------
# Keyword extraction (RAKE)
# ---------------------------------------------------------------------------

def extract_keywords(text: str, min_phrases: int = 5, max_phrases: int = 15) -> Tuple[List[str], Dict[str, float]]:
    """
    Extract key phrases using RAKE, prioritising multi-word phrases.

    Returns (keywords_list, scores_dict) where keywords_list is ordered by
    multi-word phrases first, then by descending score.
    """
    from rake_nltk import Rake

    _ensure_nltk_data()
    rake = Rake()
    rake.extract_keywords_from_text(text)

    # ranked_phrases returns list of (score, phrase) sorted by score desc
    ranked = rake.get_ranked_phrases_with_scores()

    if not ranked:
        return [], {}

    # Separate multi-word and single-word phrases
    multi_word = [(score, phrase) for score, phrase in ranked if len(phrase.split()) > 1]
    single_word = [(score, phrase) for score, phrase in ranked if len(phrase.split()) == 1]

    # Combine: multi-word first (already score-sorted), then single-word
    combined = multi_word + single_word

    # Trim to max_phrases
    combined = combined[:max_phrases]

    # Pad with remaining single-word phrases if below min_phrases
    if len(combined) < min_phrases:
        remaining = [item for item in (multi_word + single_word) if item not in combined]
        combined += remaining[: min_phrases - len(combined)]

    keywords = [phrase for _, phrase in combined]
    scores = {phrase: float(score) for score, phrase in combined}

    return keywords, scores


# ---------------------------------------------------------------------------
# Main processing handler
# ---------------------------------------------------------------------------

def process_nlp_event(event: NLPEvent, invoke_next_stage: bool = True) -> NLPResult:
    """
    Full NLP pipeline:
    1. Summarize extracted text (fallback to original on failure)
    2. Extract keywords using RAKE
    3. Store NLP data in DynamoDB
    4. Update scan metadata status to 'nlp_complete'
    5. Invoke Search Lambda asynchronously
    """
    scan_id = event.scan_id
    extracted_text = event.extracted_text

    # 1. Summarize (with fallback)
    try:
        summary = summarize(extracted_text)
    except Exception as exc:
        logger.warning(
            "[scan_id=%s] Summarization failed, using original text: %s", scan_id, exc
        )
        summary = extracted_text

    # 2. Extract keywords
    try:
        keywords, keyword_scores = extract_keywords(summary or extracted_text)
    except Exception as exc:
        raise RuntimeError(
            f"[scan_id={scan_id}] Keyword extraction failed: {exc}"
        ) from exc

    processed_at = datetime.now(timezone.utc).isoformat()

    # 3 & 4. Store NLP data and update scan metadata in DynamoDB
    try:
        ddb = get_dynamodb_resource()
        table = ddb.Table(settings.DYNAMODB_TABLE_NAME)

        # Store NLP data entity
        table.put_item(
            Item={
                "PK": f"SCAN#{scan_id}",
                "SK": "NLP_DATA",
                "summary": summary,
                "keywords": keywords,
                "keyword_scores": {k: str(v) for k, v in keyword_scores.items()},
                "processed_at": processed_at,
            }
        )

        # Update scan metadata status
        table.update_item(
            Key={"PK": f"SCAN#{scan_id}", "SK": "METADATA"},
            UpdateExpression="SET #s = :s, updated_at = :u",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":s": "nlp_complete",
                ":u": processed_at,
            },
        )
    except Exception as exc:
        raise RuntimeError(
            f"[scan_id={scan_id}] DynamoDB write failed: {exc}"
        ) from exc

    if invoke_next_stage:
        # 5. Invoke Search Lambda asynchronously
        try:
            lambda_client = get_lambda_client()
            search_payload = {
                "scan_id": scan_id,
                "user_id": event.user_id,
                "keywords": keywords,
                "summary": summary,
            }
            lambda_client.invoke(
                FunctionName=settings.SEARCH_LAMBDA_NAME,
                InvocationType="Event",  # async
                Payload=json.dumps(search_payload).encode(),
            )
        except Exception as exc:
            # Log but don't fail — NLP work is already persisted
            logger.warning(
                "[scan_id=%s] Failed to invoke Search Lambda (%s): %s",
                scan_id,
                settings.SEARCH_LAMBDA_NAME,
                exc,
            )

    return NLPResult(
        summary=summary,
        keywords=keywords,
        keyword_scores=keyword_scores,
        processed_at=processed_at,
    )
