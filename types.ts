
export type Mood = 
  | 'happy' 
  | 'tired' 
  | 'stressed' 
  | 'energetic' 
  | 'sad' 
  | 'hungry' 
  | 'lonely' 
  | 'excited' 
  | 'lazy' 
  | 'frustrated' 
  | 'anxious' 
  | 'peaceful';

export type Weather = 'sunny' | 'rainy' | 'cloudy';

export interface LocationData {
  latitude: number;
  longitude: number;
}

export interface Place {
  title: string;
  uri: string;
  rating?: string;
}

export interface Recommendation {
  dishName: string;
  reasoning: string;
  weatherContext: string;
  imageUrl?: string;
  places?: Place[];
}

export enum AppState {
  IDLE = 'IDLE',
  LOADING = 'LOADING',
  RESULT = 'RESULT',
  ERROR = 'ERROR'
}
