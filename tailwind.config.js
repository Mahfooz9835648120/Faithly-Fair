/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: { extend: { colors: { wine: '#94464d', blush: '#f9d8d9', cream: '#f7f1c8', ink: '#3f292b' }, fontFamily: { display: ['Cormorant Garamond','serif'], sans: ['DM Sans','sans-serif'], script: ['Allura','cursive'] } } },
  plugins: []
};
