
import React from 'react';
import { Mood } from '../types';
import { motion } from 'framer-motion';

interface MoodIconProps {
  mood: Mood;
  selected: boolean;
  onClick: () => void;
}

const MoodIcon: React.FC<MoodIconProps> = ({ mood, selected, onClick }) => {
  const moodConfig: Record<Mood, { icon: string; label: string }> = {
    happy: { icon: '😊', label: '행복해요' },
    tired: { icon: '😴', label: '피곤해요' },
    stressed: { icon: '😰', label: '스트레스' },
    energetic: { icon: '😃', label: '활기차요' },
    sad: { icon: '😢', label: '슬퍼요' },
    hungry: { icon: '😋', label: '배고파요' },
    lonely: { icon: '🥺', label: '외로워요' },
    excited: { icon: '🤩', label: '신나요!' },
    lazy: { icon: '🫠', label: '귀찮아요' },
    frustrated: { icon: '😤', label: '답답해요' },
    anxious: { icon: '😨', label: '불안해요' },
    peaceful: { icon: '😌', label: '평온해요' }
  };

  const config = moodConfig[mood];

  return (
    <motion.button
      onClick={onClick}
      whileTap={{ scale: 0.95 }}
      className={`flex flex-col items-center justify-center p-3 rounded-2xl transition-all duration-300 border-2 ${
        selected 
          ? 'border-[#8B4A3A] bg-[#FDF2F0] shadow-inner' 
          : 'border-transparent bg-white shadow-sm'
      }`}
    >
      <span className="text-4xl mb-2">{config.icon}</span>
      <span className={`text-[11px] font-bold ${selected ? 'text-[#8B4A3A]' : 'text-[#6A6A6A]'}`}>
        {config.label}
      </span>
    </motion.button>
  );
};

export default MoodIcon;
