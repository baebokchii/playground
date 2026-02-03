
import React from 'react';
import { Weather } from '../types.ts';
import { motion } from 'framer-motion';

interface WeatherIconProps {
  weather: Weather;
  selected: boolean;
  onClick: () => void;
}

const WeatherIcon: React.FC<WeatherIconProps> = ({ weather, selected, onClick }) => {
  const icons: Record<Weather, string> = {
    sunny: '☀️',
    rainy: '🌧️',
    cloudy: '☁️'
  };

  const labels: Record<Weather, string> = {
    sunny: '맑음',
    rainy: '비',
    cloudy: '흐림'
  };

  return (
    <motion.button
      onClick={onClick}
      whileTap={{ scale: 0.95 }}
      className={`flex flex-col items-center justify-center p-4 rounded-2xl transition-all duration-300 border-2 flex-1 ${
        selected 
          ? 'border-[#8B4A3A] bg-[#FDF2F0] shadow-inner' 
          : 'border-transparent bg-white shadow-sm'
      }`}
    >
      <span className="text-4xl mb-2">{icons[weather]}</span>
      <span className={`text-sm font-bold ${selected ? 'text-[#8B4A3A]' : 'text-[#6A6A6A]'}`}>
        {labels[weather]}
      </span>
    </motion.button>
  );
};

export default WeatherIcon;
