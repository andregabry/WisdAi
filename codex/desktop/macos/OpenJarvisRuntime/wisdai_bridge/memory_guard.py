"""Hygiene-filtered memory extractor and store layered onto OpenJarvis MemoryService."""

from __future__ import annotations

import logging
import re
from typing import List

from openjarvis.core.events import EventBus
from openjarvis.memory.extractor import FactExtractor
from openjarvis.memory.service import MemoryService
from openjarvis.memory.store import TRUST_UNTRUSTED, FactStore, create_fact_store

logger = logging.getLogger(__name__)

_STRICT_EXTRACTION_PROMPT = (
    "Extract ONLY durable long-term user preferences, communication habits, or explicit user rules "
    "from the exchange (for example: language preference, tone preference, concise summary preference). "
    "NEVER extract ephemeral workspace details such as project names, repository paths, task IDs, "
    "git branches, agent availability, files analyzed, or current errors. "
    "Respond ONLY with a JSON array of short strings (<160 chars). If none apply, respond with []."
)

_EPHEMERAL_PATTERNS = (
    re.compile(r"/Users/"),
    re.compile(r"\btask-\d+\b", re.I),
    re.compile(r"\b(auditoria|audit|running|andamento|status|branch|commit|wisdmeet|wisdfin)\b", re.I),
    re.compile(r"\b(projeto ativo|active project|agentes dispon|available agents)\b", re.I),
    re.compile(r"\b(claude code|codex|antigravity)\s+(está|is)\s+(desligado|offline|indisponível|unavailable)\b", re.I),
)


class FilteredFactExtractor(FactExtractor):
    """FactExtractor subclass filtering out volatile project/task facts."""

    def __init__(self, engine, model: str) -> None:
        super().__init__(
            engine,
            model,
            temperature=0.0,
            max_tokens=256,
            system_prompt=_STRICT_EXTRACTION_PROMPT,
        )

    def extract(self, user_text: str, assistant_text: str = "") -> List[str]:
        raw_facts = super().extract(user_text, assistant_text)
        filtered: List[str] = []
        for fact in raw_facts:
            clean = (fact or "").strip()
            if len(clean) < 6 or len(clean) > 160:
                continue
            if any(pat.search(clean) for pat in _EPHEMERAL_PATTERNS):
                continue
            filtered.append(clean)
        return filtered


def create_scoped_memory_service(
    store_path: str,
    *,
    engine,
    model: str,
    bus: EventBus,
) -> tuple[FactStore, MemoryService]:
    store = create_fact_store("local", path=store_path, max_facts=250)
    # Quarantine any accidentally persisted transient repository facts from prior runs
    try:
        for idx, existing in enumerate(store.list()):
            if any(pat.search(existing.text) for pat in _EPHEMERAL_PATTERNS):
                store.set_trust(idx, TRUST_UNTRUSTED)
    except Exception:
        logger.debug("Cleanup of transient facts skipped", exc_info=True)
    extractor = FilteredFactExtractor(engine, model)
    service = MemoryService(store, extractor, event_bus=bus)
    return store, service
