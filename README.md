<div align="center">
  <img width="1200" height="475" alt="GHBanner" src="https://github.com/user-attachments/assets/0aa67016-6eaf-458a-adb2-6e31a0763ed6" />
</div>

# 오밥뭐? — AI Weather & Mood Menu Recommender

오늘의 기분과 현재 날씨/위치를 함께 고려해 **가장 어울리는 메뉴 1개**와 **근처 맛집 2곳**을 추천해주는 AI 앱입니다.

- **라이브 날씨 검색** + **현재 위치 기반 추천**
- **기분 선택** → **메뉴 + 이유 + 맛집 링크**
- **음식 이미지 생성** (가능한 경우)

---

## ✨ 주요 기능

- **기분 선택 기반 추천**: 12가지 기분(행복/피곤/스트레스 등)을 선택하면 그에 맞는 메뉴를 추천합니다.
- **위치 + 날씨 컨텍스트 반영**: 브라우저 위치 정보를 사용해 현재 좌표를 얻고, 해당 지역의 실시간 날씨를 검색합니다.
  - 위치 권한이 없거나 실패하면 기본 위치(HKUST)를 사용합니다.
- **맛집 추천**: 추천 메뉴를 실제로 판매하는 주변 식당 2곳을 찾아 Google Maps 링크로 제공합니다.
- **이미지 생성**: 추천된 메뉴에 맞는 음식 이미지를 생성해 카드에 표시합니다.

---

## ✅ 빠른 시작 (로컬 실행)

### 1) 의존성 설치

```bash
npm install
```

### 2) 환경 변수 설정

`.env.local` 파일을 만들고 아래처럼 Gemini API 키를 추가하세요.

```bash
GEMINI_API_KEY=your_api_key_here
```

> 앱에서는 `GEMINI_API_KEY`를 `process.env.API_KEY`로 매핑하여 사용합니다.

### 3) 개발 서버 실행

```bash
npm run dev
```

브라우저에서 안내된 로컬 주소로 접속하세요.

---

## 🧠 동작 흐름 (요약)

1. 사용자가 **기분 선택**
2. 앱이 **현재 위치**를 얻고, Gemini가 **실시간 날씨**를 검색
3. 날씨 + 기분을 반영한 **메뉴 추천** 및 **추천 이유** 생성
4. 해당 메뉴를 파는 **근처 식당 2곳**을 검색
5. (가능한 경우) **메뉴 이미지 생성** 후 카드에 표시

---

## 📦 스크립트

```bash
npm run dev      # 개발 서버
npm run build    # 프로덕션 빌드
npm run preview  # 빌드 미리보기
```

---

## 🔗 AI Studio

AI Studio 앱 링크: https://ai.studio/apps/drive/1szRfDpB-8ksNHNE5B63-bTJkOC3i-4CT
