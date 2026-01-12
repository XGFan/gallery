/** @type {import('tailwindcss').Config} */
export default {
    content: [
        "./index.html",
        "./src/**/*.{js,ts,jsx,tsx}",
    ],
    theme: {
        extend: {
            colors: {
                glass: {
                    DEFAULT: 'rgba(255, 255, 255, 0.1)',
                    subtle: 'rgba(255, 255, 255, 0.05)',
                    heavy: 'rgba(30, 30, 30, 0.6)',
                    liquid: 'rgba(200, 200, 255, 0.15)',
                    highlight: 'rgba(255, 255, 255, 0.25)',
                    border: 'rgba(255, 255, 255, 0.2)',
                },
                accent: {
                    DEFAULT: '#3b82f6',
                    gradient: 'linear-gradient(135deg, #60eda8 0%, #1e5dd3 100%)',
                }
            },
            dropShadow: {
                glow: '0 0 16px rgba(255, 255, 255, 0.2)',
            },
            fontFamily: {
                sans: ['Inter', 'system-ui', 'sans-serif'],
            },
            animation: {
                'fade-in': 'fadeIn 0.5s ease-out',
                'slide-up': 'slideUp 0.5s ease-out',
                'slide-in-from-left': 'slideInFromLeft 0.3s ease-out',
                'slide-in-from-right': 'slideInFromRight 0.3s ease-out',
            },
            keyframes: {
                fadeIn: {
                    '0%': { opacity: '0' },
                    '100%': { opacity: '1' },
                },
                slideUp: {
                    '0%': { transform: 'translateY(20px)', opacity: '0' },
                    '100%': { transform: 'translateY(0)', opacity: '1' },
                },
                slideInFromLeft: {
                    '0%': { transform: 'translateX(-100%)' },
                    '100%': { transform: 'translateX(0)' },
                },
                slideInFromRight: {
                    '0%': { transform: 'translateX(100%)' },
                    '100%': { transform: 'translateX(0)' },
                },
            }
        },
    },
    plugins: [],
}

