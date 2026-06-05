import '@testing-library/jest-dom/vitest'

// jsdom doesn't implement ResizeObserver; provide a no-op so components that
// observe element size (e.g. the gallery container) can mount under test.
if (typeof globalThis.ResizeObserver === 'undefined') {
  globalThis.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
}
