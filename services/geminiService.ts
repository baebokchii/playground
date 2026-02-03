
import { GoogleGenAI } from "@google/genai";
import { Mood, Weather, LocationData, Recommendation, Place } from "../types.ts";

export const getFoodRecommendation = async (
  mood: Mood,
  weather: Weather,
  location: LocationData | null
): Promise<Recommendation> => {
  const ai = new GoogleGenAI({ apiKey: process.env.API_KEY });
  
  // HKUST Central Library Coordinates
  const lat = location?.latitude || 22.3364;
  const lng = location?.longitude || 114.2655;

  // 창의성을 위한 랜덤성 요소
  const randomnessSeed = Math.floor(Math.random() * 1000);

  const prompt = `
    당신은 홍콩과학기술대학교(HKUST) 캠퍼스와 인근 지역(Hang Hau, Sai Kung, Clear Water Bay)의 모든 음식 장르를 꿰뚫고 있는 미식 가이드입니다.

    사용자 상황:
    - 현재 위치: HKUST 캠퍼스 (위도 ${lat}, 경도 ${lng})
    - 오늘 기분: ${mood}
    - 오늘 날씨: ${weather}
    - 창의성 시드: ${randomnessSeed}

    미션 (Mood & Weather Based Surprise):
    1. 사용자의 기분과 현재 날씨를 고려할 때, 오늘 이 순간 가장 완벽할 것 같은 메뉴 1가지를 선정하세요. 음식 장르는 중식, 일식, 한식, 양식, 홍콩식 등 무엇이든 상관없습니다.
    2. 기분에 따라 위로가 되는 음식(Comfort Food), 활력을 주는 음식, 혹은 스트레스를 날려줄 자극적인 음식 등 심리학적인 요소를 메뉴 선정에 반영하세요.
    3. googleMaps 도구를 사용하여 **선정한 메뉴를 전문적으로 판매하는 실제 식당**만 딱 2곳 찾으세요.
    4. **엄격한 필터링 기준**: 
       - 구글 평점이 반드시 **4.0점 이상**인 곳만 추천하세요.
       - '스타벅스', '편의점', '학교 건물', '서점', '디저트 전용 카페' 등 식사가 아닌 곳은 절대 제외하세요.
    5. **위치 전략**: 
       - HKUST 캠퍼스 내부 식당(LG1, LG7, G/F 등)을 최우선으로 찾고, 적절한 곳이 없다면 항하우(Hang Hau)나 사이쿵(Sai Kung) 지역으로 범위를 넓히세요.
    6. 답변 형식 (반드시 이 형식을 유지):
       [메뉴: 메뉴이름(영문명)]
       [이유: 이 메뉴가 사용자의 현재 기분과 날씨에 왜 최고의 선택인지에 대한 설명 2문장]
       [날씨: 날씨와 음식의 조화를 강조하는 짧은 위트 코멘트]
       [평점정보: 식당명1:평점 / 식당명2:평점]
  `;

  const response = await ai.models.generateContent({
    model: "gemini-3-flash-preview",
    contents: prompt,
    config: {
      temperature: 1.0,
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
  
  const dishNameMatch = text.match(/\[메뉴:\s*(.*?)\]/);
  const reasoningMatch = text.match(/\[이유:\s*(.*?)\]/);
  const weatherContextMatch = text.match(/\[날씨:\s*(.*?)\]/);
  const ratingInfoMatch = text.match(/\[평점정보:\s*(.*?)\]/);

  const dishName = dishNameMatch ? dishNameMatch[1] : "추천 메뉴";
  const reasoning = reasoningMatch ? reasoningMatch[1] : text.split('\n')[0];
  const weatherContext = weatherContextMatch ? weatherContextMatch[1] : "오늘 날씨에 딱이에요!";
  const ratingInfoStr = ratingInfoMatch ? ratingInfoMatch[1] : "";

  const ratingMap = new Map<string, string>();
  if (ratingInfoStr) {
    ratingInfoStr.split('/').forEach(item => {
      const parts = item.split(':').map(s => s.trim());
      if (parts.length >= 2) {
        ratingMap.set(parts[0], parts[1]);
      }
    });
  }

  const places: Place[] = [];
  const chunks = response.candidates?.[0]?.groundingMetadata?.groundingChunks || [];
  
  for (const [name, rating] of ratingMap.entries()) {
    const chunk = chunks.find(c => c.maps && (c.maps.title?.toLowerCase().includes(name.toLowerCase()) || name.toLowerCase().includes(c.maps.title?.toLowerCase() || "")));
    if (chunk && chunk.maps) {
      places.push({
        title: chunk.maps.title || name,
        uri: chunk.maps.uri || "",
        rating: rating
      });
      if (places.length >= 2) break;
    }
  }

  if (places.length < 2) {
    for (const chunk of chunks) {
      if (chunk.maps && !places.some(p => p.uri === chunk.maps?.uri)) {
        const title = chunk.maps.title || "";
        const blackList = ["university", "library", "hall", "starbucks", "convenience", "7-eleven", "bookstore", "student"];
        if (blackList.some(b => title.toLowerCase().includes(b))) continue;

        places.push({
          title: title,
          uri: chunk.maps.uri || "",
          rating: ratingMap.get(title) || "4.1+"
        });
        if (places.length >= 2) break;
      }
    }
  }

  try {
    const imageResult = await generateFoodImage(dishName);
    return { 
      dishName, 
      reasoning, 
      weatherContext, 
      imageUrl: imageResult,
      places: places.length > 0 ? places.slice(0, 2) : undefined
    };
  } catch (error) {
    return { dishName, reasoning, weatherContext, places: places.length > 0 ? places.slice(0, 2) : undefined };
  }
};

const generateFoodImage = async (dishName: string): Promise<string | undefined> => {
  const ai = new GoogleGenAI({ apiKey: process.env.API_KEY });
  const response = await ai.models.generateContent({
    model: 'gemini-2.5-flash-image',
    contents: {
      parts: [{ text: `A mouth-watering, high-quality photograph of ${dishName}. Beautiful plating on a wooden table, warm ambient lighting, highly detailed food textures, 8k resolution, cinematic style.` }],
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
