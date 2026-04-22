#!/usr/bin/env python3
"""
한국어기초사전 Open API를 사용하여 hanja.txt 단어들의 정의를 수집합니다.
결과는 definitions.json으로 저장됩니다.

Usage:
  python3 fetch_definitions.py [--limit N] [--resume]

  --limit N   : 최대 N개 단어만 조회 (테스트용)
  --resume    : 기존 definitions.json이 있으면 이어서 수집
"""

import json
import os
import ssl
import sys
import time
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET

# SSL 인증서 검증 우회 (한국 정부 사이트 자체서명 인증서)
ssl_ctx = ssl.create_default_context()
ssl_ctx.check_hostname = False
ssl_ctx.verify_mode = ssl.CERT_NONE

API_KEY = "7E36329C837372B4F8D927F8BF8B3DBD"
API_URL = "https://krdict.korean.go.kr/api/search"
HANJA_FILE = os.path.join(os.path.dirname(__file__), "..", "HanjaWidget", "HanjaWidget", "hanja.txt")
OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "..", "HanjaWidget", "HanjaWidget", "definitions.json")

def is_hangul(c):
    return '\uAC00' <= c <= '\uD7AF'

def load_words_from_hanja():
    """hanja.txt에서 2글자 이상 한글 단어와 대응 한자를 추출"""
    word_hanja = {}  # korean -> set of hanja variants
    with open(HANJA_FILE, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split(':')
            if len(parts) < 2:
                continue
            korean = parts[0]
            hanja = parts[1]
            korean_only = ''.join(c for c in korean if is_hangul(c))
            hanja_only = ''.join(c for c in hanja if '\u4E00' <= c <= '\u9FFF' or '\u3400' <= c <= '\u4DBF' or '\uF900' <= c <= '\uFAFF' or is_hangul(c))
            if len(korean_only) >= 2 and hanja_only:
                if korean_only not in word_hanja:
                    word_hanja[korean_only] = set()
                word_hanja[korean_only].add(hanja_only)
    return word_hanja

def search_api(query):
    """한국어기초사전 API로 단어 검색"""
    params = urllib.parse.urlencode({
        'key': API_KEY,
        'q': query,
        'part': 'word',
        'sort': 'dict',
        'num': 10,
        'method': 'exact',  # 정확히 일치하는 것만
    })
    url = f"{API_URL}?{params}"

    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req, timeout=10, context=ssl_ctx) as resp:
            return resp.read().decode('utf-8')
    except Exception as e:
        print(f"  API error for '{query}': {e}")
        return None

def parse_response(xml_text, target_hanja_set):
    """XML 응답에서 한자 origin이 매칭되는 항목의 정의를 추출"""
    results = {}
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return results

    for item in root.findall('.//item'):
        word = item.findtext('word', '')
        origin = item.findtext('origin', '')
        if not origin:
            continue

        # origin이 우리 hanja 목록에 있는지 확인
        if origin in target_hanja_set:
            senses = []
            for sense in item.findall('.//sense'):
                definition = sense.findtext('definition', '')
                if definition:
                    senses.append(definition)
            if senses:
                results[origin] = senses

    return results

def main():
    limit = None
    resume = False
    for arg in sys.argv[1:]:
        if arg == '--resume':
            resume = True
        elif arg.startswith('--limit'):
            pass
        else:
            try:
                limit = int(arg)
            except ValueError:
                pass

    # --limit N 형태 파싱
    for i, arg in enumerate(sys.argv[1:], 1):
        if arg == '--limit' and i < len(sys.argv) - 1:
            limit = int(sys.argv[i + 1])

    print("hanja.txt에서 단어 로딩 중...")
    word_hanja = load_words_from_hanja()
    print(f"  고유 한글 단어: {len(word_hanja)}개")

    # 기존 결과 로드 (resume 모드)
    existing = {}
    already_queried = set()
    if resume and os.path.exists(OUTPUT_FILE):
        with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
            existing = json.load(f)
        already_queried = set(existing.get('_queried_words', []))
        print(f"  기존 결과: {len(existing) - 1}개 정의, {len(already_queried)}개 조회 완료")

    # 조회 대상 필터링
    words_to_query = [(k, v) for k, v in word_hanja.items() if k not in already_queried]
    if limit:
        words_to_query = words_to_query[:limit]

    print(f"  조회 대상: {len(words_to_query)}개")
    print()

    definitions = {k: v for k, v in existing.items() if k != '_queried_words'}
    queried = list(already_queried)
    found = 0
    not_found = 0
    errors = 0

    for i, (korean, hanja_set) in enumerate(words_to_query):
        if (i + 1) % 50 == 0 or i == 0:
            print(f"[{i+1}/{len(words_to_query)}] 조회 중... (발견: {found}, 미발견: {not_found})")

        xml = search_api(korean)
        queried.append(korean)

        if xml is None:
            errors += 1
            if errors > 10:
                print("에러가 너무 많아 중단합니다.")
                break
            time.sleep(1)
            continue

        matches = parse_response(xml, hanja_set)
        if matches:
            for hanja, senses in matches.items():
                key = f"{korean}:{hanja}"
                definitions[key] = senses
                found += 1
        else:
            not_found += 1

        # Rate limiting: ~5 requests/sec
        time.sleep(0.2)

        # 중간 저장 (500개마다)
        if (i + 1) % 500 == 0:
            save_data = dict(definitions)
            save_data['_queried_words'] = queried
            with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
                json.dump(save_data, f, ensure_ascii=False, indent=2)
            print(f"  중간 저장 완료 ({len(definitions)}개 정의)")

    # 최종 저장
    save_data = dict(definitions)
    save_data['_queried_words'] = queried
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        json.dump(save_data, f, ensure_ascii=False, indent=2)

    print()
    print(f"완료!")
    print(f"  총 조회: {len(words_to_query)}개")
    print(f"  정의 발견: {found}개")
    print(f"  미발견: {not_found}개")
    print(f"  에러: {errors}개")
    print(f"  저장: {OUTPUT_FILE}")

if __name__ == '__main__':
    main()
