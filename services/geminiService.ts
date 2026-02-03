
import { GoogleGenAI } from "@google/genai";
import { Mood, Weather, LocationData, Recommendation, Place } from "../types.ts";

export const getFoodRecommendation = async (
  mood: Mood,
  weather: Weather,
  location: LocationData | null
): Promise<Recommendation> => {
  const apiKey = process.env.API_KEY;
  if (!apiKey) {
    throw new Error("API_KEY가 설정되지 않았습니다. Vercel 환경 변수를 확인해주세요.");
  }

  const ai = new GoogleGenAI({ apiKey });
  
  // 위치 정보 처리
  const lat = location?.latitude;
  const lng = location?.longitude;
  
  // 홍콩 HKUST 대략적 범위 체크 (22.3~22.4, 114.2~114.3)
  const isNearHKUST = lat && lng && lat > 22.3 && lat < 22.4 && lng > 114.2 && lng < 114.3;

  const locationContext = isNearHKUST 
    ? "당신은 홍콩과학기술대학교(HKUST) 캠퍼스 전문가입니다. 캠퍼스 내(LG1, LG7 등) 혹은 근처 항하우 맛집을 추천하세요."
    : "당신은 현재 사용자가 있는 지역의 미식 가이드입니다. 사용자의 좌표 주변에서 가장 어울리는 음식을 추천하세요.";

  const prompt = `
    ${locationContext}
    현재 상태: 기분(${mood}), 날씨(${weather})
    현재 좌표: 위도 ${lat || '22.3364'}, 경도 ${lng || '114.2655'}

    [미션]
    1. 'googleMaps' 도구를 사용해 이 좌표 주변에서 추천 메뉴를 판매하는 실제 식당 2곳을 찾으세요.
    2. 아래 형식을 반드시 포함하여 답변하세요:
    
    [메뉴: 메뉴이름]
    [이유: 추천 이유 1-2문장]
    [날씨: 날씨와 음식의 조화 코멘트]
    [식당: 식당명1, 식당명2]
  `;

  try {
    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash", 
      contents: prompt,
      config: {
        temperature: 0.8,
        tools: [{ googleMaps: {} }, { googleSearch: {} }],
        toolConfig: {
          retrievalConfig: {
            latLng: (lat && lng) ? { latitude: lat, longitude: lng } : { latitude: 22.3364, longitude: 114.2655 }
          }
        }
      }
    });

    const text = response.text || "";
    
    // 더 정교하고 유연한 정규식 파싱
    const getMatch = (tag: string) => {
      const regex = new RegExp(`\\[${tag}:\\s*(.*?)\\]`, 'i');
      const match = text.match(regex);
      return match ? match[1].trim() : null;
    };

    const dishName = getMatch("메뉴") || "오늘의 특별식";
    const reasoning = getMatch("이유") || "당신을 위해 엄선한 메뉴입니다.";
    const weatherContext = getMatch("날씨") || "오늘 날씨에 즐기기 아주 좋아요.";
    const rawRestaurants = getMatch("식당");

    const places: Place[] = [];
    const chunks = response.candidates?.[0]?.groundingMetadata?.groundingChunks || [];
    
    // 1. 구글 지도 Grounding 데이터 매칭
    for (const chunk of chunks) {
      if (chunk.maps && chunk.maps.title) {
        if (!places.some(p => p.title === chunk.maps?.title)) {
          places.push({
            title: chunk.maps.title,
            uri: chunk.maps.uri || `https://www.google.com/maps/search/${encodeURIComponent(chunk.maps.title)}`,
            rating: "4.2+"
          });
        }
      }
    }

    // 2. 파싱된 식당명이 있고 Grounding이 부족할 때 보완
    if (places.length < 2 && rawRestaurants) {
      rawRestaurants.split(',').map(n => n.trim()).forEach(name => {
        if (name && !places.some(p => p.title.includes(name))) {
          places.push({
            title: name,
            uri: `https://www.google.com/maps/search/${encodeURIComponent(name)}`,
            rating: "4.0+"
          });
        }
      });
    }

    // 이미지 생성 (실패해도 전체 프로세스는 성공해야 함)
    let imageUrl: string | undefined;
    try {
      imageUrl = await generateFoodImage(dishName);
    } catch (e) {
      console.warn("이미지 생성 건너뜀");
    }

    return { 
      dishName, 
      reasoning, 
      weatherContext, 
      imageUrl,
      places: places.length > 0 ? places.slice(0, 2) : undefined
    };
  } catch (error) {
    console.error("추천 생성 중 오류:", error);
    throw error;
  }
};

const generateFoodImage = async (dishName: string): Promise<string | undefined> => {
  const ai = new GoogleGenAI({ apiKey: process.env.API_KEY });
  try {
    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash-image',
      contents: {
        parts: [{ text: `A mouth-watering, professional food photography of ${dishName}. High quality, warm lighting.` }],
      },
      config: { imageConfig: { aspectRatio: "1:1" } },
    });

    const part = response.candidates?.[0]?.content?.parts?.find(p => p.inlineData);
    return part?.inlineData ? `data:image/png;base64,${part.inlineData.data}` : undefined;
  } catch (e) {
    return undefined;
  }
};
