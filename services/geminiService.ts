
import { GoogleGenAI } from "@google/genai";
import { Mood, LocationData, Recommendation, Place } from "../types.ts";

export const getFoodRecommendation = async (
  mood: Mood,
  location: LocationData | null
): Promise<Recommendation> => {
  const apiKey = process.env.API_KEY;
  if (!apiKey) {
    throw new Error("API_KEY가 설정되지 않았습니다.");
  }

  const ai = new GoogleGenAI({ apiKey });
  
  // 위치 정보 처리 (기본값: HKUST)
  const lat = location?.latitude || 22.3364;
  const lng = location?.longitude || 114.2655;

  const prompt = `
    사용자 현재 좌표: 위도 ${lat}, 경도 ${lng}
    사용자 기분: ${mood}

    [필수 단계]
    1. 'googleSearch' 도구를 사용하여 위 좌표의 '현재 실시간 날씨(기온, 날씨 상태 등)'를 검색하세요.
    2. 검색된 날씨와 사용자의 기분에 가장 잘 어울리는 메뉴 1개를 선정하세요.
    3. 'googleMaps' 도구를 사용하여 해당 위치 주변에서 그 메뉴를 판매하는 실제 식당 2곳을 찾으세요. 만약 HKUST 근처라면 캠퍼스 내 식당을 우선순위로 두세요.

    [답변 형식 - 반드시 이 형식을 지키세요]
    [날씨정보: 검색된 현재 날씨 요약 (예: 맑음, 25도)]
    [메뉴: 메뉴이름]
    [이유: 기분과 날씨를 고려한 추천 이유 1-2문장]
    [식당: 식당명1, 식당명2]
  `;

  try {
    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash", 
      contents: prompt,
      config: {
        temperature: 0.7,
        tools: [{ googleSearch: {} }, { googleMaps: {} }],
        toolConfig: {
          retrievalConfig: {
            latLng: { latitude: lat, longitude: lng }
          }
        }
      }
    });

    const text = response.text || "";
    
    const getMatch = (tag: string) => {
      const regex = new RegExp(`\\[${tag}:\\s*(.*?)\\]`, 'i');
      const match = text.match(regex);
      return match ? match[1].trim() : null;
    };

    const weatherInfo = getMatch("날씨정보") || "날씨 정보를 확인했습니다.";
    const dishName = getMatch("메뉴") || "오늘의 추천 메뉴";
    const reasoning = getMatch("이유") || "현재 날씨와 기분에 딱 맞는 선택이에요.";
    const rawRestaurants = getMatch("식당");

    const places: Place[] = [];
    const chunks = response.candidates?.[0]?.groundingMetadata?.groundingChunks || [];
    
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

    let imageUrl: string | undefined;
    try {
      imageUrl = await generateFoodImage(dishName);
    } catch (e) {
      console.warn("이미지 생성 건너뜀");
    }

    return { 
      dishName, 
      reasoning, 
      weatherContext: weatherInfo, 
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
        parts: [{ text: `High-quality, appetizing food photography of ${dishName}. Beautiful lighting, close-up.` }],
      },
      config: { imageConfig: { aspectRatio: "1:1" } },
    });
    const part = response.candidates?.[0]?.content?.parts?.find(p => p.inlineData);
    return part?.inlineData ? `data:image/png;base64,${part.inlineData.data}` : undefined;
  } catch (e) {
    return undefined;
  }
};
