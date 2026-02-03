
import { GoogleGenAI } from "@google/genai";
import { Mood, Weather, LocationData, Recommendation, Place } from "../types.ts";

export const getFoodRecommendation = async (
  mood: Mood,
  weather: Weather,
  location: LocationData | null
): Promise<Recommendation> => {
  // 새 인스턴스 생성 (최신 API 키 반영 보장)
  const ai = new GoogleGenAI({ apiKey: process.env.API_KEY });
  
  // 기본 위치: HKUST (사용자 위치 정보가 없을 경우 대비)
  const lat = location?.latitude || 22.3364;
  const lng = location?.longitude || 114.2655;

  const randomnessSeed = Math.floor(Math.random() * 1000);

  const prompt = `
    당신은 홍콩과학기술대학교(HKUST) 학생들을 위한 최고의 미식 큐레이터입니다. 
    오늘의 기분(${mood})과 날씨(${weather})를 조합해 지금 이 순간 가장 완벽한 메뉴를 하나 추천해 주세요.
    
    위치 정보: 위도 ${lat}, 경도 ${lng} (HKUST 캠퍼스 근처)

    요구사항:
    1. 음식 장르는 제한 없으나, 캠퍼스 생활에 활력을 줄 수 있는 메뉴여야 합니다.
    2. 'googleMaps' 도구를 사용하여 해당 메뉴를 실제로 판매하는 HKUST 캠퍼스 내 혹은 인근(Hang Hau, Sai Kung 등) 식당 2곳을 찾으세요.
    3. 반드시 실제 존재하는 식당이어야 하며, 도서관이나 강의실 등 식당이 아닌 곳은 제외하세요.
    4. 아래 형식을 엄격히 지켜 답변하세요:
    
    [메뉴: 메뉴이름(영문명)]
    [이유: 추천 이유 2문장]
    [날씨: 날씨 조화 코멘트]
    [식당: 식당이름1, 식당이름2]
  `;

  try {
    const response = await ai.models.generateContent({
      // CRITICAL FIX: Google Maps grounding is only supported in Gemini 2.5 series
      model: "gemini-2.5-flash-lite-latest",
      contents: prompt,
      config: {
        temperature: 0.9,
        tools: [{ googleMaps: {} }, { googleSearch: {} }],
        toolConfig: {
          retrievalConfig: {
            latLng: {
              latitude: lat,
              longitude: lng
            }
          }
        }
      }
    });

    const text = response.text || "";
    
    // 데이터 추출
    const dishName = text.match(/\[메뉴:\s*(.*?)\]/)?.[1] || "스페셜 메뉴";
    const reasoning = text.match(/\[이유:\s*(.*?)\]/)?.[1] || "오늘 당신의 기분과 날씨에 딱 맞는 최고의 선택이에요.";
    const weatherContext = text.match(/\[날씨:\s*(.*?)\]/)?.[1] || "오늘 날씨와 아주 잘 어울려요.";
    const restaurantNames = text.match(/\[식당:\s*(.*?)\]/)?.[1]?.split(',').map(s => s.trim()) || [];

    const places: Place[] = [];
    const chunks = response.candidates?.[0]?.groundingMetadata?.groundingChunks || [];
    
    // 식당 정보 매칭 및 생성
    for (const chunk of chunks) {
      if (chunk.maps && chunk.maps.title) {
        if (!places.some(p => p.uri === chunk.maps?.uri)) {
          places.push({
            title: chunk.maps.title,
            uri: chunk.maps.uri || `https://www.google.com/maps/search/${encodeURIComponent(chunk.maps.title)}`,
            rating: "4.2+"
          });
        }
      }
    }

    // Grounding에서 부족할 경우 텍스트에서 추출한 이름으로 보완
    if (places.length === 0 && restaurantNames.length > 0) {
      restaurantNames.forEach(name => {
        if (name && name.length > 1) {
          places.push({
            title: name,
            uri: `https://www.google.com/maps/search/${encodeURIComponent(name)}`,
            rating: "4.0+"
          });
        }
      });
    }

    // 이미지 생성 (별도 호출)
    let imageUrl: string | undefined;
    try {
      imageUrl = await generateFoodImage(dishName);
    } catch (e) {
      console.warn("Image generation failed", e);
    }

    return { 
      dishName, 
      reasoning, 
      weatherContext, 
      imageUrl,
      places: places.length > 0 ? places.slice(0, 2) : undefined
    };
  } catch (error) {
    console.error("Gemini API Error:", error);
    throw error; // App.tsx의 catch 블록으로 전달
  }
};

const generateFoodImage = async (dishName: string): Promise<string | undefined> => {
  const ai = new GoogleGenAI({ apiKey: process.env.API_KEY });
  const response = await ai.models.generateContent({
    model: 'gemini-2.5-flash-image',
    contents: {
      parts: [{ text: `A vibrant, high-quality close-up photograph of ${dishName}. Professional food photography, delicious lighting, soft background, 4k.` }],
    },
    config: { imageConfig: { aspectRatio: "1:1" } },
  });

  for (const part of response.candidates?.[0]?.content?.parts || []) {
    if (part.inlineData) {
      return `data:image/png;base64,${part.inlineData.data}`;
    }
  }
  return undefined;
};
