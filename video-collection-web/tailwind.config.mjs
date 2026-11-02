/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  theme: {
    extend: {
      colors: {
        slate: { 50: '#f7f9ff', 100: '#eff3fc', 200: '#e3e9f8', 300: '#c1cae4', 400: '#8994b6', 500: '#717e9e', 600: '#576384', 700: '#454f73', 800: '#353b58', 900: '#222b50' },
        brand: { blue: '#4b9fff', purple: '#9a83ff', pink: '#ff89c7', ink: '#353b58' },
        primary: {
          50: '#f1f5ff',
          100: '#e6edff',
          200: '#d5e0ff',
          300: '#b6d2ff',
          400: '#80b6ff',
          500: '#4b9fff',
          600: '#597bea',
          700: '#5265c6',
          800: '#46539c',
          900: '#353b58',
        },
        anime: {
          dark: '#0f172a',
          card: '#ffffff',
          bg: '#f8fafc',
          border: '#e2e8f0',
          muted: '#64748b',
          gold: '#f59e0b'
        }
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', '"Segoe UI"', 'Roboto', '"PingFang SC"', '"Hiragino Sans GB"', '"Microsoft YaHei"', 'sans-serif'],
      },
      boxShadow: {
        'soft': '0 4px 20px -2px rgba(0, 0, 0, 0.05)',
        'card-hover': '0 12px 28px -4px rgba(37, 99, 235, 0.12)',
        'glow': '0 0 25px -5px rgba(59, 130, 246, 0.35)',
      }
    },
  },
  plugins: [],
};
