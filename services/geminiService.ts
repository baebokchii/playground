
import { GoogleGenAI } from "@google/genai";
import { Mood, Weather, LocationData, Recommendation, Place } from "../types.ts";

export const getFoodRecommendation = async (
  mood: Mood,
  weather: Weather,
  location: LocationData | null
): Promise<Recommendation> => {
  // 새 인스턴스 생성 (API 키 접근 보장)
  const ai = new GoogleGenAI({ apiKey: process.env.API_KEY });
  
  // 기본 위치: HKUST
  const lat = location?.latitude || 22.3364;
  const lng = location?.longitude || 114.2655;

  const prompt = `
    당신은 홍콩과학기술대학교(HKUST) 캠퍼스 미식 전문가입니다.
    사용자 상태: 기분(${mood}), 날씨(${weather})
    위치: HKUST 캠퍼스 근처 (위도 ${lat}, 경도 ${lng})

    요구사항:
    1. 이 상황에 어울리는 구체적인 메뉴 1개를 선정하세요.
    2. 'googleMaps' 도구를 사용해 HKUST 캠퍼스 내 혹은 항하우(Hang Hau) 지역의 실제 식당 2곳을 찾으세요.
    3. 반드시 아래 형식을 포함해 답변하세요 (데이터 추출을 위해 매우 중요함):
    
    [메뉴: 메뉴이름]
    [이유: 추천 이유 설명]
    [날씨: 날씨 관련 코멘트]
    [식당: 식당명1, 식당명2]
  `;

  try {
    // Maps Grounding은 Gemini 2.5 시리즈 모델에서 지원됨
    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash", 
      contents: prompt,
      config: {
        temperature: 0.8,
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
    if (!text) throw new Error("API가 빈 응답을 반환했습니다.");

    // 유연한 데이터 추출 로직
    const extract = (tag: string, fallback: string) => {
      const regex = new RegExp(`\\[${tag}:\\s*(.*?)\\]`, 'i');
      const match = text.match(regex);
      return match ? match[1].trim() : fallback;
    };

    const dishName = extract("메뉴", "오늘의 추천 메뉴");
    const reasoning = extract("이유", text.split('\n')[0] || "당신의 기분과 날씨를 고려한 최고의 선택입니다.");
    const weatherContext = extract("날씨", "오늘 날씨에 정말 잘 어울리는 메뉴예요.");
    const rawRestaurants = extract("식당", "");

    const places: Place[] = [];
    const chunks = response.candidates?.[0]?.groundingMetadata?.groundingChunks || [];
    
    // 1. 구글 지도 Grounding 데이터에서 식당 정보 추출
    for (const chunk of chunks) {
      if (chunk.maps && chunk.maps.title) {
        if (!places.some(p => p.title === chunk.maps?.title)) {
          places.push({
            title: chunk.maps.title,
            uri: chunk.maps.uri || `https://www.google.com/maps/search/${encodeURIComponent(chunk.maps.title)}`,
            rating: "4.1+"
          });
        }
      }
    }

    // 2. 텍스트에서 명시된 식당명이 Grounding에 없을 경우 보완
    if (places.length < 2 && rawRestaurants) {
      const names = rawRestaurants.split(',').map(n => n.trim()).filter(n => n.length > 0);
      names.forEach(name => {
        if (!places.some(p => p.title.includes(name) || name.includes(p.title))) {
          places.push({
            title: name,
            uri: `https://www.google.com/maps/search/${encodeURIComponent(name)}`,
            rating: "4.0+"
          });
        }
      });
    }

    // 이미지 생성
    let imageUrl: string | undefined;
    try {
      imageUrl = await generateFoodImage(dishName);
    } catch (e) {
      console.warn("이미지 생성 실패:", e);
    }

    return { 
      dishName, 
      reasoning, 
      weatherContext, 
      imageUrl,
      places: places.length > 0 ? places.slice(0, 2) : undefined
    };
  } catch (error) {
    console.error("Gemini 서비스 상세 에러:", error);
    throw error; 
  }
};

const generateFoodImage = async (dishName: string): Promise<string | undefined> => {
  const ai = new GoogleGenAI({ apiKey: process.env.API_KEY });
  const response = await ai.models.generateContent({
    model: 'gemini-2.5-flash-image',
    contents: {
      parts: [{ text: `A professional, appetizing food photography of ${dishName}. High resolution, beautiful plating, soft natural lighting, macro shot.` }],
    },
    config: { imageConfig: { aspectRatio: "1:1" } },
  });

  const part = response.candidates?.[0]?.content?.parts?.find(p => p.inlineData);
  return part?.inlineData ? `data:image/png;base64,${part.inlineData.data}` : undefined;
};
