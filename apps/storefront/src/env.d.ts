/// <reference types="vite/client" />

declare module '*.vue' {
  import { DefineComponent } from 'vue'
  const component: DefineComponent
  export default component
}

declare const wx: {
  cloud?: { init(options: { env: string; traceUser: boolean }): void; callFunction(options: { name: string; data: Record<string, unknown>; config?: { env: string } }): Promise<{ result: unknown; requestID?: string }> }
}
