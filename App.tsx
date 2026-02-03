
import React, { useState } from 'react';
import { Mood, Weather, Recommendation, AppState, LocationData } from './types.ts';
import { getFoodRecommendation } from './services/geminiService.ts';
import MoodIcon from './components/MoodIcon.tsx';
import WeatherIcon from './components/WeatherIcon.tsx';
import { motion, AnimatePresence } from 'framer-motion';

const SectionTitle = ({ children }: { children: React.ReactNode }) => (
  <div className="flex items-center gap-2 mb-4">
    <div className="w-1 h-5 bg-[#6B3A2E] rounded-full"></div>
    <h3 className="text-lg font-bold text-[#2D2D2D]">{children}</h3>
  </div>
);

export default function App() {
  const [mood, setMood] = useState<Mood>('happy');
  const [weather, setWeather] = useState<Weather>('sunny');
  const [appState, setAppState] = useState<AppState>(AppState.IDLE);
  const [result, setResult] = useState<Recommendation | null>(null);

  const moods: Mood[] = [
    'happy', 'tired', 'stressed', 'energetic', 'sad', 'hungry',
    'lonely', 'excited', 'lazy', 'frustrated', 'anxious', 'peaceful'
  ];
  const weathers: Weather[] = ['sunny', 'cloudy', 'rainy'];

  const handleRecommend = async () => {
    setAppState(AppState.LOADING);
    let location: LocationData | null = null;
    
    try {
      const pos = await new Promise<GeolocationPosition>((res, rej) => 
        navigator.geolocation.getCurrentPosition(res, rej, { timeout: 5000 })
      );
      location = { latitude: pos.coords.latitude, longitude: pos.coords.longitude };
    } catch (e) { 
      console.warn("GPS 사용 불가 - 기본 위치(HKUST)를 사용합니다."); 
    }

    try {
      const data = await getFoodRecommendation(mood, weather, location);
      setResult(data);
      setAppState(AppState.RESULT);
    } catch (error) {
      console.error("Recommendation failed:", error);
      setAppState(AppState.ERROR);
    }
  };

  const reset = () => {
    setAppState(AppState.IDLE);
    setResult(null);
  };

  return (
    <div className="min-h-screen bg-[#FFF9F6] text-[#2D2D2D] font-['Pretendard']">
      <header className="px-6 py-5 flex items-center justify-between sticky top-0 bg-[#FFF9F6]/80 backdrop-blur-md z-10">
        <h1 className="text-xl font-bold text-[#8B4A3A] tracking-tight">오밥뭐?</h1>
        <div className="px-3 py-1 bg-[#8B4A3A] text-white text-[10px] font-bold rounded-lg tracking-wider">HKUST CAMPUS</div>
      </header>

      <main className="max-w-md mx-auto px-6 pt-2 pb-12">
        <AnimatePresence mode="wait">
          {appState === AppState.IDLE && (
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="space-y-8">
              <section>
                <h2 className="text-3xl font-black mb-2 text-[#2D2D2D]">오늘 밥 뭐 먹을까?</h2>
                <p className="text-[#8E8E8E] font-medium">홍콩의 날씨와 당신의 기분을 맞춰보세요.</p>
              </section>

              <div className="space-y-8">
                <section>
                  <SectionTitle children="지금 기분은 어떤가요?" />
                  <div className="grid grid-cols-3 gap-2.5">
                    {moods.map((m) => (
                      <MoodIcon key={m} mood={m} selected={mood === m} onClick={() => setMood(m)} />
                    ))}
                  </div>
                </section>

                <section>
                  <SectionTitle children="창밖의 날씨는?" />
                  <div className="flex gap-2.5">
                    {weathers.map((w) => (
                      <WeatherIcon key={w} weather={w} selected={weather === w} onClick={() => setWeather(w)} />
                    ))}
                  </div>
                </section>

                <button 
                  onClick={handleRecommend}
                  className="w-full bg-[#8B4A3A] hover:bg-[#6B3A2E] text-white py-5 rounded-[2rem] font-bold text-lg flex items-center justify-center gap-2 transition-all shadow-xl shadow-[#8B4A3A]/20 active:scale-95"
                >
                  메뉴 추천받기 <span className="text-xl">→</span>
                </button>
              </div>
            </motion.div>
          )}

          {appState === AppState.LOADING && (
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="flex flex-col items-center justify-center py-40">
              <div className="relative w-24 h-24 mb-8">
                <div className="absolute inset-0 border-[6px] border-[#FDF2F0] rounded-full"></div>
                <div className="absolute inset-0 border-[6px] border-t-[#8B4A3A] rounded-full animate-spin"></div>
              </div>
              <h2 className="text-xl font-bold text-center text-[#8B4A3A] leading-relaxed">
                오늘 같은 날, 당신을 위한<br/>최고의 한 끼를 찾고 있어요...
              </h2>
            </motion.div>
          )}

          {appState === AppState.RESULT && result && (
            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="space-y-6">
              <div className="bg-white rounded-[3rem] overflow-hidden shadow-2xl border border-[#F5EDE8]">
                {result.imageUrl && (
                  <div className="relative">
                    <img src={result.imageUrl} alt={result.dishName} className="w-full aspect-square object-cover" />
                    <div className="absolute bottom-0 left-0 right-0 h-24 bg-gradient-to-t from-white to-transparent"></div>
                  </div>
                )}
                <div className="p-8 -mt-6 relative bg-white rounded-t-[3rem]">
                  <div className="mb-6">
                    <div className="inline-block px-4 py-1.5 bg-[#FDF2F0] text-[#8B4A3A] text-xs font-bold rounded-full mb-4 shadow-sm">
                      {result.weatherContext}
                    </div>
                    <h2 className="text-3xl font-black text-[#8B4A3A] mb-3 leading-tight">{result.dishName}</h2>
                    <p className="text-lg font-medium leading-relaxed text-[#4A4A4A]">{result.reasoning}</p>
                  </div>

                  {result.places && result.places.length > 0 && (
                    <div className="pt-8 border-t border-[#F5EDE8]">
                      <div className="flex items-center justify-between mb-6">
                        <div className="flex items-center gap-2">
                          <span className="text-xl">⭐</span>
                          <h4 className="font-bold text-[#8B4A3A]">평점 4.0+ 추천 맛집</h4>
                        </div>
                      </div>
                      <div className="space-y-3">
                        {result.places.map((place, idx) => (
                          <a 
                            key={idx} 
                            href={place.uri} 
                            target="_blank" 
                            rel="noopener noreferrer"
                            className="flex items-center justify-between p-5 bg-[#FDF2F0]/40 rounded-2xl border border-transparent hover:border-[#8B4A3A]/30 hover:bg-white transition-all group shadow-sm"
                          >
                            <div className="flex flex-col gap-1 overflow-hidden">
                              <span className="font-bold text-[#2D2D2D] group-hover:text-[#8B4A3A] truncate">{place.title}</span>
                              <span className="text-xs font-bold text-[#8B4A3A] flex items-center gap-1">
                                <span className="text-amber-400">★</span> {place.rating}
                              </span>
                            </div>
                            <span className="bg-white p-2.5 rounded-full shadow-sm text-[#8B4A3A] group-hover:bg-[#8B4A3A] group-hover:text-white transition-colors">
                              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><path d="M7 17l10-10M7 7h10v10"/></svg>
                            </span>
                          </a>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              </div>
              <button onClick={reset} className="w-full bg-[#8B4A3A] text-white py-5 rounded-[2rem] font-bold text-lg shadow-xl hover:bg-[#6B3A2E] transition-colors active:scale-95">다른 메뉴 추천받기</button>
            </motion.div>
          )}

          {appState === AppState.ERROR && (
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="flex flex-col items-center justify-center py-40 text-center">
              <div className="bg-[#FDF2F0] w-24 h-24 rounded-full flex items-center justify-center mb-8">
                <span className="text-5xl">🏜️</span>
              </div>
              <h2 className="text-2xl font-black mb-3 text-[#2D2D2D]">추천을 가져오지 못했어요</h2>
              <p className="text-[#8E8E8E] mb-10 leading-relaxed font-medium">네트워크 연결을 확인하거나<br/>잠시 후 다시 시도해주세요.</p>
              <button onClick={reset} className="bg-[#8B4A3A] text-white px-10 py-4 rounded-2xl font-bold shadow-lg">홈으로 돌아가기</button>
            </motion.div>
          )}
        </AnimatePresence>
      </main>
    </div>
  );
}
